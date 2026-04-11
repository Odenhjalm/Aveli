from __future__ import annotations

from contextlib import closing
from datetime import datetime, timezone
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from socket import socket
import threading
import uuid

import pytest

from app import db
from app.config import settings
from app.repositories import courses as courses_repo
from app.repositories import media_assets as media_assets_repo
from app.services import storage_service as storage_service_module

pytestmark = pytest.mark.anyio("asyncio")


def _auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _free_local_port() -> int:
    with closing(socket()) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


class _StorageSignHandler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:  # noqa: N802
        if not self.path.startswith("/storage/v1/object/sign/"):
            self.send_response(404)
            self.end_headers()
            return
        if "missing-object" in self.path:
            payload = {"error": "not_found", "message": "Object not found"}
            encoded = json.dumps(payload).encode("utf-8")
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)
            return
        signed_url = self.path.removeprefix("/storage/v1")
        if "?" not in signed_url:
            signed_url = f"{signed_url}?token=test-token"
        payload = {"signedURL": signed_url}
        encoded = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        del format, args


class _StaticUrl:
    def __init__(self, url: str) -> None:
        self._url = url

    def unicode_string(self) -> str:
        return self._url


@pytest.fixture
def local_storage_signer(monkeypatch):
    original_url = settings.supabase_url
    original_services = dict(storage_service_module._storage_services)
    port = _free_local_port()
    server = ThreadingHTTPServer(("127.0.0.1", port), _StorageSignHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    storage_service_module._storage_services.clear()
    monkeypatch.setattr(settings, "supabase_url", _StaticUrl(f"http://127.0.0.1:{port}"))
    try:
        yield
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        storage_service_module._storage_services.clear()
        storage_service_module._storage_services.update(original_services)
        monkeypatch.setattr(settings, "supabase_url", original_url)


async def _register_user(
    async_client,
    *,
    email: str,
    password: str,
    display_name: str,
) -> tuple[dict[str, str], str]:
    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": display_name,
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    headers = _auth_header(tokens["access_token"])
    me_resp = await async_client.get("/profiles/me", headers=headers)
    assert me_resp.status_code == 200, me_resp.text
    return headers, me_resp.json()["user_id"]


async def _promote_to_teacher(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                update app.auth_subjects
                   set role_v2 = 'teacher',
                       role = 'teacher'
                 where user_id = %s::uuid
                """,
                (user_id,),
            )
            await conn.commit()


async def _cleanup_state(
    *,
    upload_ids: list[str] | None = None,
    link_ids: list[str] | None = None,
    lesson_media_ids: list[str] | None = None,
    media_asset_ids: list[str] | None = None,
    lesson_ids: list[str] | None = None,
    course_ids: list[str] | None = None,
    user_ids: list[str] | None = None,
) -> None:
    upload_ids = upload_ids or []
    link_ids = link_ids or []
    lesson_media_ids = lesson_media_ids or []
    media_asset_ids = media_asset_ids or []
    lesson_ids = lesson_ids or []
    course_ids = course_ids or []
    user_ids = user_ids or []

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            for upload_id in upload_ids:
                await cur.execute(
                    "delete from app.home_player_uploads where id = %s::uuid",
                    (upload_id,),
                )
            for link_id in link_ids:
                await cur.execute(
                    "delete from app.home_player_course_links where id = %s::uuid",
                    (link_id,),
                )
            for lesson_media_id in lesson_media_ids:
                await cur.execute(
                    "delete from app.lesson_media where id = %s::uuid",
                    (lesson_media_id,),
                )
            for media_asset_id in media_asset_ids:
                await cur.execute(
                    "delete from app.media_assets where id = %s::uuid",
                    (media_asset_id,),
                )
            for lesson_id in lesson_ids:
                await cur.execute(
                    "delete from app.lesson_contents where lesson_id = %s::uuid",
                    (lesson_id,),
                )
                await cur.execute(
                    "delete from app.lessons where id = %s::uuid",
                    (lesson_id,),
                )
            for course_id in course_ids:
                await cur.execute(
                    "delete from app.course_enrollments where course_id = %s::uuid",
                    (course_id,),
                )
                await cur.execute(
                    "delete from app.course_public_content where course_id = %s::uuid",
                    (course_id,),
                )
                await cur.execute(
                    "delete from app.courses where id = %s::uuid",
                    (course_id,),
                )
            for user_id in user_ids:
                await cur.execute(
                    "delete from app.refresh_tokens where user_id = %s::uuid",
                    (user_id,),
                )
                await cur.execute(
                    "delete from auth.users where id = %s::uuid",
                    (user_id,),
                )
            await conn.commit()


async def _insert_course(
    *,
    course_id: str,
    owner_id: str,
    slug: str,
    title: str,
    is_published: bool,
) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.courses (
                  id,
                  title,
                  slug,
                  course_group_id,
                  step,
                  price_amount_cents,
                  drip_enabled,
                  drip_interval_days,
                  cover_media_id,
                  created_by,
                  is_published
                )
                values (
                  %s::uuid,
                  %s,
                  %s,
                  %s::uuid,
                  'step1'::app.course_step,
                  1000,
                  false,
                  null,
                  null,
                  %s::uuid,
                  %s
                )
                """,
                (course_id, title, slug, str(uuid.uuid4()), owner_id, is_published),
            )
            await conn.commit()


async def _insert_lesson(*, lesson_id: str, course_id: str, title: str, position: int) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.lessons (
                  id,
                  course_id,
                  lesson_title,
                  position
                )
                values (%s::uuid, %s::uuid, %s, %s)
                """,
                (lesson_id, course_id, title, position),
            )
            await cur.execute(
                """
                insert into app.lesson_contents (lesson_id, content_markdown)
                values (%s::uuid, '# Lesson')
                on conflict (lesson_id) do nothing
                """,
                (lesson_id,),
            )
            await conn.commit()


async def _insert_media_asset(
    *,
    media_asset_id: str,
    owner_id: str,
    course_id: str | None,
    lesson_id: str | None,
    purpose: str,
    state: str,
    ready_path: str | None = None,
) -> None:
    insert_state = "uploaded" if state == "ready" else state
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.media_assets (
                  id,
                  owner_id,
                  course_id,
                  lesson_id,
                  media_type,
                  purpose,
                  original_object_path,
                  ingest_format,
                  playback_object_path,
                  playback_format,
                  state,
                  original_content_type,
                  original_filename,
                  original_size_bytes,
                  storage_bucket
                )
                values (
                  %s::uuid,
                  %s::uuid,
                  %s::uuid,
                  %s::uuid,
                  'audio'::app.media_type,
                  %s::app.media_purpose,
                  %s,
                  'wav',
                  %s,
                  %s,
                  %s::app.media_state,
                  'audio/wav',
                  'demo.wav',
                  512,
                  'course-media'
                )
                """,
                (
                    media_asset_id,
                    owner_id,
                    course_id,
                    lesson_id,
                    purpose,
                    f"media/source/audio/{uuid.uuid4().hex}.wav",
                    None,
                    None,
                    insert_state,
                ),
            )
            await conn.commit()

    if state == "ready":
        assert ready_path is not None
        await media_assets_repo.mark_media_asset_ready_from_worker(
            media_id=media_asset_id,
            playback_object_path=ready_path,
        )


async def _insert_lesson_media(
    *,
    lesson_media_id: str,
    lesson_id: str,
    media_asset_id: str,
    position: int = 1,
) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.lesson_media (
                  id,
                  lesson_id,
                  media_asset_id,
                  position
                )
                values (%s::uuid, %s::uuid, %s::uuid, %s)
                """,
                (lesson_media_id, lesson_id, media_asset_id, position),
            )
            await conn.commit()


async def _insert_home_player_upload(
    *,
    upload_id: str,
    teacher_id: str,
    media_asset_id: str,
    title: str,
    active: bool,
) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.home_player_uploads (
                  id,
                  teacher_id,
                  media_id,
                  media_asset_id,
                  title,
                  kind,
                  active
                )
                values (%s::uuid, %s::uuid, null, %s::uuid, %s, 'audio', %s)
                """,
                (upload_id, teacher_id, media_asset_id, title, active),
            )
            await conn.commit()


async def _insert_home_player_course_link(
    *,
    link_id: str,
    teacher_id: str,
    lesson_media_id: str,
    title: str,
    enabled: bool,
    course_title_snapshot: str,
) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.home_player_course_links (
                  id,
                  teacher_id,
                  lesson_media_id,
                  title,
                  course_title_snapshot,
                  enabled
                )
                values (%s::uuid, %s::uuid, %s::uuid, %s, %s, %s)
                """,
                (link_id, teacher_id, lesson_media_id, title, course_title_snapshot, enabled),
            )
            await conn.commit()


def _find_item(items: list[dict], media_asset_id: str) -> dict | None:
    return next(
        (
            item
            for item in items
            if str((item.get("media") or {}).get("media_id") or "") == media_asset_id
        ),
        None,
    )


@pytest.mark.anyio("asyncio")
async def test_home_audio_db_direct_upload_respects_active_owner_and_media_asset_playback(
    async_client,
    local_storage_signer,
):
    del local_storage_signer
    upload_ids: list[str] = []
    media_asset_ids: list[str] = []
    user_ids: list[str] = []

    teacher_headers, teacher_id = await _register_user(
        async_client,
        email=f"home_audio_db_teacher_{uuid.uuid4().hex[:6]}@example.org",
        password="Passw0rd!",
        display_name="Teacher",
    )
    user_ids.append(teacher_id)
    await _promote_to_teacher(teacher_id)
    other_headers, other_id = await _register_user(
        async_client,
        email=f"home_audio_db_other_{uuid.uuid4().hex[:6]}@example.org",
        password="Passw0rd!",
        display_name="Other",
    )
    user_ids.append(other_id)

    active_asset_id = str(uuid.uuid4())
    inactive_asset_id = str(uuid.uuid4())
    active_upload_id = str(uuid.uuid4())
    inactive_upload_id = str(uuid.uuid4())
    media_asset_ids.extend([active_asset_id, inactive_asset_id])
    upload_ids.extend([active_upload_id, inactive_upload_id])

    try:
        await _insert_media_asset(
            media_asset_id=active_asset_id,
            owner_id=teacher_id,
            course_id=None,
            lesson_id=None,
            purpose="home_player_audio",
            state="ready",
            ready_path=f"media/derived/audio/home/{uuid.uuid4().hex}.mp3",
        )
        await _insert_media_asset(
            media_asset_id=inactive_asset_id,
            owner_id=teacher_id,
            course_id=None,
            lesson_id=None,
            purpose="home_player_audio",
            state="ready",
            ready_path=f"media/derived/audio/home/{uuid.uuid4().hex}.mp3",
        )
        await _insert_home_player_upload(
            upload_id=active_upload_id,
            teacher_id=teacher_id,
            media_asset_id=active_asset_id,
            title="Active direct upload",
            active=True,
        )
        await _insert_home_player_upload(
            upload_id=inactive_upload_id,
            teacher_id=teacher_id,
            media_asset_id=inactive_asset_id,
            title="Inactive direct upload",
            active=False,
        )

        teacher_resp = await async_client.get("/home/audio", headers=teacher_headers)
        assert teacher_resp.status_code == 200, teacher_resp.text
        items = teacher_resp.json()["items"]
        visible = _find_item(items, active_asset_id)
        assert visible is not None
        assert visible["source_type"] == "direct_upload"
        assert visible["title"] == "Active direct upload"
        assert visible["teacher_id"] == teacher_id
        assert visible["media"]["media_id"] == active_asset_id
        assert visible["media"]["state"] == "ready"
        assert visible["media"]["resolved_url"]
        assert f"/course-media/media/derived/audio/home/" in visible["media"]["resolved_url"]
        assert _find_item(items, inactive_asset_id) is None

        other_resp = await async_client.get("/home/audio", headers=other_headers)
        assert other_resp.status_code == 200, other_resp.text
        assert _find_item(other_resp.json()["items"], active_asset_id) is None
    finally:
        await _cleanup_state(
            upload_ids=upload_ids,
            media_asset_ids=media_asset_ids,
            user_ids=user_ids,
        )


@pytest.mark.anyio("asyncio")
async def test_home_audio_db_course_link_respects_enabled_and_canonical_lesson_access(
    async_client,
):
    link_ids: list[str] = []
    lesson_media_ids: list[str] = []
    media_asset_ids: list[str] = []
    lesson_ids: list[str] = []
    course_ids: list[str] = []
    user_ids: list[str] = []

    teacher_headers, teacher_id = await _register_user(
        async_client,
        email=f"home_audio_course_teacher_{uuid.uuid4().hex[:6]}@example.org",
        password="Passw0rd!",
        display_name="Teacher",
    )
    user_ids.append(teacher_id)
    await _promote_to_teacher(teacher_id)
    student_headers, student_id = await _register_user(
        async_client,
        email=f"home_audio_course_student_{uuid.uuid4().hex[:6]}@example.org",
        password="Passw0rd!",
        display_name="Student",
    )
    user_ids.append(student_id)

    course_id = str(uuid.uuid4())
    lesson_id = str(uuid.uuid4())
    media_asset_id = str(uuid.uuid4())
    lesson_media_id = str(uuid.uuid4())
    link_id = str(uuid.uuid4())
    course_ids.append(course_id)
    lesson_ids.append(lesson_id)
    media_asset_ids.append(media_asset_id)
    lesson_media_ids.append(lesson_media_id)
    link_ids.append(link_id)

    try:
        await _insert_course(
            course_id=course_id,
            owner_id=teacher_id,
            slug=f"home-audio-course-{uuid.uuid4().hex[:8]}",
            title="Home Audio Course",
            is_published=True,
        )
        await _insert_lesson(
            lesson_id=lesson_id,
            course_id=course_id,
            title="Lesson 1",
            position=1,
        )
        await _insert_media_asset(
            media_asset_id=media_asset_id,
            owner_id=teacher_id,
            course_id=course_id,
            lesson_id=lesson_id,
            purpose="lesson_media",
            state="uploaded",
        )
        await _insert_lesson_media(
            lesson_media_id=lesson_media_id,
            lesson_id=lesson_id,
            media_asset_id=media_asset_id,
        )
        await _insert_home_player_course_link(
            link_id=link_id,
            teacher_id=teacher_id,
            lesson_media_id=lesson_media_id,
            title="Course-linked track",
            enabled=True,
            course_title_snapshot="Home Audio Course",
        )

        teacher_resp = await async_client.get("/home/audio", headers=teacher_headers)
        assert teacher_resp.status_code == 200, teacher_resp.text
        teacher_item = _find_item(teacher_resp.json()["items"], media_asset_id)
        assert teacher_item is None

        await courses_repo.create_course_enrollment(
            user_id=teacher_id,
            course_id=course_id,
            source="purchase",
        )
        teacher_enrolled_resp = await async_client.get("/home/audio", headers=teacher_headers)
        assert teacher_enrolled_resp.status_code == 200, teacher_enrolled_resp.text
        teacher_item = _find_item(teacher_enrolled_resp.json()["items"], media_asset_id)
        assert teacher_item is not None
        assert teacher_item["source_type"] == "course_link"
        assert teacher_item["media"]["state"] == "uploaded"
        assert teacher_item["media"]["resolved_url"] is None

        student_resp = await async_client.get("/home/audio", headers=student_headers)
        assert student_resp.status_code == 200, student_resp.text
        assert _find_item(student_resp.json()["items"], media_asset_id) is None

        await courses_repo.create_course_enrollment(
            user_id=student_id,
            course_id=course_id,
            source="purchase",
        )
        student_enrolled_resp = await async_client.get("/home/audio", headers=student_headers)
        assert student_enrolled_resp.status_code == 200, student_enrolled_resp.text
        student_item = _find_item(student_enrolled_resp.json()["items"], media_asset_id)
        assert student_item is not None
        assert student_item["media"]["media_id"] == media_asset_id

        async with db.pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    "update app.home_player_course_links set enabled = false where id = %s::uuid",
                    (link_id,),
                )
                await conn.commit()

        disabled_resp = await async_client.get("/home/audio", headers=teacher_headers)
        assert disabled_resp.status_code == 200, disabled_resp.text
        assert _find_item(disabled_resp.json()["items"], media_asset_id) is None
    finally:
        await _cleanup_state(
            link_ids=link_ids,
            lesson_media_ids=lesson_media_ids,
            media_asset_ids=media_asset_ids,
            lesson_ids=lesson_ids,
            course_ids=course_ids,
            user_ids=user_ids,
        )


@pytest.mark.anyio("asyncio")
async def test_home_audio_db_non_ready_items_keep_resolved_url_null(async_client):
    upload_ids: list[str] = []
    media_asset_ids: list[str] = []
    user_ids: list[str] = []

    teacher_headers, teacher_id = await _register_user(
        async_client,
        email=f"home_audio_nonready_teacher_{uuid.uuid4().hex[:6]}@example.org",
        password="Passw0rd!",
        display_name="Teacher",
    )
    user_ids.append(teacher_id)
    await _promote_to_teacher(teacher_id)

    media_asset_id = str(uuid.uuid4())
    upload_id = str(uuid.uuid4())
    media_asset_ids.append(media_asset_id)
    upload_ids.append(upload_id)

    try:
        await _insert_media_asset(
            media_asset_id=media_asset_id,
            owner_id=teacher_id,
            course_id=None,
            lesson_id=None,
            purpose="home_player_audio",
            state="uploaded",
        )
        await _insert_home_player_upload(
            upload_id=upload_id,
            teacher_id=teacher_id,
            media_asset_id=media_asset_id,
            title="Uploaded direct upload",
            active=True,
        )

        resp = await async_client.get("/home/audio", headers=teacher_headers)
        assert resp.status_code == 200, resp.text
        item = _find_item(resp.json()["items"], media_asset_id)
        assert item is not None
        assert item["media"]["state"] == "uploaded"
        assert item["media"]["resolved_url"] is None
    finally:
        await _cleanup_state(
            upload_ids=upload_ids,
            media_asset_ids=media_asset_ids,
            user_ids=user_ids,
        )


@pytest.mark.anyio("asyncio")
async def test_home_audio_db_invalid_ready_items_are_filtered(async_client, local_storage_signer):
    del local_storage_signer
    upload_ids: list[str] = []
    media_asset_ids: list[str] = []
    user_ids: list[str] = []

    teacher_headers, teacher_id = await _register_user(
        async_client,
        email=f"home_audio_invalid_teacher_{uuid.uuid4().hex[:6]}@example.org",
        password="Passw0rd!",
        display_name="Teacher",
    )
    user_ids.append(teacher_id)
    await _promote_to_teacher(teacher_id)

    good_asset_id = str(uuid.uuid4())
    bad_asset_id = str(uuid.uuid4())
    good_upload_id = str(uuid.uuid4())
    bad_upload_id = str(uuid.uuid4())
    media_asset_ids.extend([good_asset_id, bad_asset_id])
    upload_ids.extend([good_upload_id, bad_upload_id])

    try:
        await _insert_media_asset(
            media_asset_id=good_asset_id,
            owner_id=teacher_id,
            course_id=None,
            lesson_id=None,
            purpose="home_player_audio",
            state="ready",
            ready_path=f"media/derived/audio/home/{uuid.uuid4().hex}.mp3",
        )
        await _insert_media_asset(
            media_asset_id=bad_asset_id,
            owner_id=teacher_id,
            course_id=None,
            lesson_id=None,
            purpose="home_player_audio",
            state="ready",
            ready_path=f"media/derived/audio/home/missing-object-{uuid.uuid4().hex}.mp3",
        )
        await _insert_home_player_upload(
            upload_id=good_upload_id,
            teacher_id=teacher_id,
            media_asset_id=good_asset_id,
            title="Good ready upload",
            active=True,
        )
        await _insert_home_player_upload(
            upload_id=bad_upload_id,
            teacher_id=teacher_id,
            media_asset_id=bad_asset_id,
            title="Bad ready upload",
            active=True,
        )

        resp = await async_client.get("/home/audio", headers=teacher_headers)
        assert resp.status_code == 200, resp.text
        items = resp.json()["items"]
        assert _find_item(items, good_asset_id) is not None
        assert _find_item(items, bad_asset_id) is None
    finally:
        await _cleanup_state(
            upload_ids=upload_ids,
            media_asset_ids=media_asset_ids,
            user_ids=user_ids,
        )
