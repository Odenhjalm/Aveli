from __future__ import annotations

import asyncio
import hashlib
import importlib
import importlib.util
import inspect
from datetime import datetime, timezone
from types import ModuleType
from uuid import UUID

from fastapi.routing import APIRoute
from httpx import ASGITransport, AsyncClient
import pytest

from app import schemas
from app.main import app
from app.routes import studio
from app.services import media_upload_sessions as upload_service
from app.services import media_upload_spool


RouteKey = tuple[str, str]

CREATE_SESSION_ROUTE: RouteKey = (
    "POST",
    "/api/home-player/media-assets/upload-url",
)
UPLOAD_CHUNK_ROUTE: RouteKey = (
    "PUT",
    "/api/media-assets/{media_asset_id}/upload-sessions/{upload_session_id}/chunks/{chunk_index}",
)
SESSION_STATUS_ROUTE: RouteKey = (
    "GET",
    "/api/media-assets/{media_asset_id}/upload-sessions/{upload_session_id}/status",
)
FINALIZE_SESSION_ROUTE: RouteKey = (
    "POST",
    "/api/media-assets/{media_asset_id}/upload-sessions/{upload_session_id}/finalize",
)


def _route_method_pairs() -> set[RouteKey]:
    pairs: set[RouteKey] = set()
    for route in app.routes:
        path = getattr(route, "path", None)
        methods = getattr(route, "methods", None)
        if not path or not methods:
            continue
        for method in methods:
            if method not in {"HEAD", "OPTIONS"}:
                pairs.add((str(method).upper(), str(path)))
    return pairs


def _required_route(route_key: RouteKey) -> APIRoute:
    method, path = route_key
    for route in app.routes:
        if not isinstance(route, APIRoute):
            continue
        if route.path == path and method in (route.methods or set()):
            return route
    raise AssertionError(f"Missing canonical chunk upload route: {method} {path}")


def _required_module(module_name: str) -> ModuleType:
    spec = importlib.util.find_spec(module_name)
    assert spec is not None, f"Missing backend upload-session module: {module_name}"
    return importlib.import_module(module_name)


def _model_fields(model_name: str) -> set[str]:
    model = getattr(schemas, model_name, None)
    assert model is not None, f"Missing schema model: {model_name}"
    return set(model.model_fields)


def _assert_fields(model_name: str, required_fields: set[str]) -> None:
    fields = _model_fields(model_name)
    assert sorted(required_fields - fields) == []


def _upload_session(
    *,
    total_bytes: int = 20,
    chunk_size: int = 8,
    expected_chunks: int = 3,
) -> dict[str, object]:
    return {
        "id": "55555555-5555-5555-5555-555555555555",
        "media_asset_id": "33333333-3333-3333-3333-333333333333",
        "owner_user_id": "44444444-4444-4444-4444-444444444444",
        "state": "open",
        "total_bytes": total_bytes,
        "content_type": "audio/wav",
        "chunk_size": chunk_size,
        "expected_chunks": expected_chunks,
        "received_bytes": 0,
        "expires_at": datetime(2099, 1, 1, tzinfo=timezone.utc),
    }


def _chunk_row(
    *,
    sha256: str,
    chunk_index: int = 0,
    byte_start: int = 0,
    byte_end: int = 7,
    size_bytes: int = 8,
) -> dict[str, object]:
    return {
        "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        "upload_session_id": "55555555-5555-5555-5555-555555555555",
        "media_asset_id": "33333333-3333-3333-3333-333333333333",
        "chunk_index": chunk_index,
        "byte_start": byte_start,
        "byte_end": byte_end,
        "size_bytes": size_bytes,
        "sha256": sha256,
        "spool_object_path": "media-upload-sessions/asset/session/chunks/00000000.part",
        "created_at": datetime(2026, 1, 1, tzinfo=timezone.utc),
    }


def test_home_player_chunk_upload_routes_are_mounted_in_canonical_api_surface() -> None:
    expected_routes = {
        CREATE_SESSION_ROUTE,
        UPLOAD_CHUNK_ROUTE,
        SESSION_STATUS_ROUTE,
        FINALIZE_SESSION_ROUTE,
    }

    assert sorted(expected_routes - _route_method_pairs()) == []


def test_home_player_upload_session_schemas_define_resume_contract() -> None:
    _assert_fields(
        "CanonicalHomePlayerMediaUploadUrlResponse",
        {
            "media_asset_id",
            "asset_state",
            "upload_session_id",
            "upload_endpoint",
            "chunk_upload_url_template",
            "session_status_endpoint",
            "finalize_endpoint",
            "chunk_size",
            "expected_chunks",
            "expires_at",
        },
    )
    _assert_fields(
        "CanonicalMediaUploadSessionStatusResponse",
        {
            "upload_session_id",
            "media_asset_id",
            "owner_user_id",
            "state",
            "asset_state",
            "total_bytes",
            "content_type",
            "chunk_size",
            "expected_chunks",
            "received_bytes",
            "expires_at",
            "chunks",
        },
    )
    _assert_fields(
        "CanonicalMediaUploadChunkResponse",
        {
            "upload_session_id",
            "media_asset_id",
            "chunk_index",
            "byte_start",
            "byte_end",
            "size_bytes",
            "sha256",
            "received_bytes",
        },
    )
    _assert_fields(
        "CanonicalMediaUploadFinalizeResponse",
        {"upload_session_id", "media_asset_id", "asset_state"},
    )


def test_home_player_upload_session_response_advertises_callable_chunk_endpoint() -> None:
    media_asset_id = UUID("33333333-3333-3333-3333-333333333333")
    upload_session_id = "55555555-5555-5555-5555-555555555555"

    response = studio._home_player_upload_session_response(
        media_asset_id=media_asset_id,
        session={
            **_upload_session(),
            "id": upload_session_id,
            "chunk_size": 8,
            "expected_chunks": 3,
        },
    )

    assert response.upload_endpoint == (
        f"/api/media-assets/{media_asset_id}/upload-sessions/"
        f"{upload_session_id}/chunks/0"
    )
    assert response.chunk_upload_url_template == (
        f"/api/media-assets/{media_asset_id}/upload-sessions/"
        f"{upload_session_id}/chunks/{{chunk_index}}"
    )


@pytest.mark.anyio("asyncio")
async def test_advertised_chunk_endpoint_is_reachable_before_auth() -> None:
    endpoint = (
        "/api/media-assets/33333333-3333-3333-3333-333333333333"
        "/upload-sessions/55555555-5555-5555-5555-555555555555/chunks/0"
    )
    transport = ASGITransport(app=app, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        preflight = await client.options(
            endpoint,
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "PUT",
                "Access-Control-Request-Headers": (
                    "authorization,content-type,content-range,x-aveli-chunk-sha256"
                ),
            },
        )
        put_response = await client.put(
            endpoint,
            content=b"chunk",
            headers={
                "Origin": "http://localhost:3000",
                "Content-Type": "audio/wav",
                "Content-Range": "bytes 0-4/5",
                "X-Aveli-Chunk-Sha256": hashlib.sha256(b"chunk").hexdigest(),
            },
        )

    assert preflight.status_code == 200
    assert put_response.status_code == 401
    assert put_response.status_code not in {404, 405}


def test_chunk_range_validation_accepts_only_exact_contiguous_ranges() -> None:
    session = _upload_session(total_bytes=20, chunk_size=8, expected_chunks=3)

    assert upload_service._parse_content_range(
        "bytes 0-7/20",
        chunk_index=0,
        content_length=8,
        session=session,
    ) == (0, 7, 8)
    assert upload_service._parse_content_range(
        "bytes 8-15/20",
        chunk_index=1,
        content_length=8,
        session=session,
    ) == (8, 15, 8)
    assert upload_service._parse_content_range(
        "bytes 16-19/20",
        chunk_index=2,
        content_length=4,
        session=session,
    ) == (16, 19, 4)


@pytest.mark.parametrize(
    ("content_range", "chunk_index", "content_length"),
    [
        ("bytes 0-11/20", 0, 12),
        ("bytes 9-15/20", 1, 7),
        ("bytes 8-14/20", 1, 7),
        ("bytes 16-18/20", 2, 3),
        ("bytes 24-25/20", 3, 2),
    ],
)
def test_chunk_range_validation_rejects_overlap_gap_and_wrong_ends(
    content_range: str,
    chunk_index: int,
    content_length: int,
) -> None:
    with pytest.raises(upload_service.UploadChunkRangeError):
        upload_service._parse_content_range(
            content_range,
            chunk_index=chunk_index,
            content_length=content_length,
            session=_upload_session(total_bytes=20, chunk_size=8, expected_chunks=3),
        )


@pytest.mark.anyio("asyncio")
async def test_receive_chunk_idempotent_retry_is_noop(monkeypatch) -> None:
    digest = hashlib.sha256(b"abcdefgh").hexdigest()
    session = _upload_session()
    existing = _chunk_row(sha256=digest)

    async def fake_get_session(**kwargs):
        return dict(session)

    async def fake_get_chunk(**kwargs):
        return dict(existing)

    async def fail_write_chunk(**kwargs):
        raise AssertionError("idempotent retry must not rewrite spool bytes")

    monkeypatch.setattr(
        upload_service.upload_sessions_repo,
        "get_upload_session_for_owner_media_asset",
        fake_get_session,
        raising=True,
    )
    monkeypatch.setattr(
        upload_service.upload_sessions_repo,
        "get_upload_chunk",
        fake_get_chunk,
        raising=True,
    )
    monkeypatch.setattr(
        upload_service.media_upload_spool,
        "write_chunk",
        fail_write_chunk,
        raising=True,
    )

    response = await upload_service.receive_home_player_upload_chunk(
        media_asset_id=str(session["media_asset_id"]),
        upload_session_id=str(session["id"]),
        owner_user_id=str(session["owner_user_id"]),
        chunk_index=0,
        content=b"abcdefgh",
        content_range="bytes 0-7/20",
        content_length=8,
        content_type="audio/wav",
        chunk_sha256=digest,
    )

    assert response["sha256"] == digest
    assert response["chunk_index"] == 0


@pytest.mark.anyio("asyncio")
async def test_receive_chunk_conflicting_retry_fails_closed(monkeypatch) -> None:
    session = _upload_session()
    existing = _chunk_row(sha256=hashlib.sha256(b"abcdefgh").hexdigest())

    async def fake_get_session(**kwargs):
        return dict(session)

    async def fake_get_chunk(**kwargs):
        return dict(existing)

    monkeypatch.setattr(
        upload_service.upload_sessions_repo,
        "get_upload_session_for_owner_media_asset",
        fake_get_session,
        raising=True,
    )
    monkeypatch.setattr(
        upload_service.upload_sessions_repo,
        "get_upload_chunk",
        fake_get_chunk,
        raising=True,
    )

    with pytest.raises(upload_service.UploadChunkConflictError):
        await upload_service.receive_home_player_upload_chunk(
            media_asset_id=str(session["media_asset_id"]),
            upload_session_id=str(session["id"]),
            owner_user_id=str(session["owner_user_id"]),
            chunk_index=0,
            content=b"XXXXXXXX",
            content_range="bytes 0-7/20",
            content_length=8,
            content_type="audio/wav",
            chunk_sha256=hashlib.sha256(b"XXXXXXXX").hexdigest(),
        )


@pytest.mark.anyio("asyncio")
async def test_spool_concurrent_same_chunk_writes_do_not_corrupt(
    tmp_path,
    monkeypatch,
) -> None:
    monkeypatch.setattr(media_upload_spool, "_SPOOL_ROOT", tmp_path, raising=True)
    content = b"same chunk bytes"
    digest = hashlib.sha256(content).hexdigest()

    first, second = await asyncio.gather(
        media_upload_spool.write_chunk(
            media_asset_id="asset-1",
            upload_session_id="session-1",
            chunk_index=0,
            content=content,
            expected_sha256=digest,
            expected_size_bytes=len(content),
        ),
        media_upload_spool.write_chunk(
            media_asset_id="asset-1",
            upload_session_id="session-1",
            chunk_index=0,
            content=content,
            expected_sha256=digest,
            expected_size_bytes=len(content),
        ),
    )

    assert first["sha256"] == digest
    assert second["sha256"] == digest
    final_path = media_upload_spool._path_for_logical_path(
        str(first["spool_object_path"])
    )
    assert final_path.read_bytes() == content


@pytest.mark.anyio("asyncio")
async def test_spool_concurrent_conflicting_chunk_write_rejects_without_corruption(
    tmp_path,
    monkeypatch,
) -> None:
    monkeypatch.setattr(media_upload_spool, "_SPOOL_ROOT", tmp_path, raising=True)
    first_content = b"first chunk"
    second_content = b"second bytes"
    first_digest = hashlib.sha256(first_content).hexdigest()
    second_digest = hashlib.sha256(second_content).hexdigest()

    results = await asyncio.gather(
        media_upload_spool.write_chunk(
            media_asset_id="asset-1",
            upload_session_id="session-1",
            chunk_index=0,
            content=first_content,
            expected_sha256=first_digest,
            expected_size_bytes=len(first_content),
        ),
        media_upload_spool.write_chunk(
            media_asset_id="asset-1",
            upload_session_id="session-1",
            chunk_index=0,
            content=second_content,
            expected_sha256=second_digest,
            expected_size_bytes=len(second_content),
        ),
        return_exceptions=True,
    )

    successes = [item for item in results if isinstance(item, dict)]
    conflicts = [
        item
        for item in results
        if isinstance(item, media_upload_spool.SpoolChunkConflictError)
    ]
    assert len(successes) == 1
    assert len(conflicts) == 1
    final_path = media_upload_spool._path_for_logical_path(
        str(successes[0]["spool_object_path"])
    )
    assert hashlib.sha256(final_path.read_bytes()).hexdigest() == successes[0]["sha256"]


@pytest.mark.anyio("asyncio")
async def test_finalize_succeeds_only_with_complete_verified_chunk_set(
    monkeypatch,
) -> None:
    session = _upload_session(total_bytes=4, chunk_size=2, expected_chunks=2)
    chunks = [
        _chunk_row(
            sha256=hashlib.sha256(b"aa").hexdigest(),
            chunk_index=0,
            byte_start=0,
            byte_end=1,
            size_bytes=2,
        ),
        _chunk_row(
            sha256=hashlib.sha256(b"bb").hexdigest(),
            chunk_index=1,
            byte_start=2,
            byte_end=3,
            size_bytes=2,
        ),
    ]
    reconstructed: dict[str, object] = {}

    async def fake_get_session(**kwargs):
        return dict(session)

    async def fake_list_chunks(**kwargs):
        return [dict(row) for row in chunks]

    async def fake_reconstruct_source_object(**kwargs):
        reconstructed.update(kwargs)
        return kwargs["destination_object_path"]

    async def fake_fetch_storage_object_existence(pairs):
        return {tuple(pair): True for pair in pairs}, True

    async def fake_mark_uploaded(*, media_id: str):
        return {"id": media_id, "state": "uploaded"}

    async def fake_mark_finalized(**kwargs):
        return {
            **dict(session),
            "state": "finalized",
            "finalized_at": datetime.now(timezone.utc),
        }

    async def fake_delete_spool(**kwargs):
        return None

    monkeypatch.setattr(
        upload_service.upload_sessions_repo,
        "get_upload_session_for_owner_media_asset",
        fake_get_session,
        raising=True,
    )
    monkeypatch.setattr(
        upload_service.upload_sessions_repo,
        "list_upload_chunks",
        fake_list_chunks,
        raising=True,
    )
    monkeypatch.setattr(
        upload_service.media_upload_spool,
        "reconstruct_source_object",
        fake_reconstruct_source_object,
        raising=True,
    )
    monkeypatch.setattr(
        upload_service.storage_objects,
        "fetch_storage_object_existence",
        fake_fetch_storage_object_existence,
        raising=True,
    )
    monkeypatch.setattr(
        upload_service.media_assets_repo,
        "mark_lesson_media_pipeline_asset_uploaded",
        fake_mark_uploaded,
        raising=True,
    )
    monkeypatch.setattr(
        upload_service.upload_sessions_repo,
        "mark_upload_session_finalized",
        fake_mark_finalized,
        raising=True,
    )
    monkeypatch.setattr(
        upload_service.media_upload_spool,
        "delete_session_spool",
        fake_delete_spool,
        raising=True,
    )

    response = await upload_service.finalize_home_player_upload_session(
        media_asset={
            "id": session["media_asset_id"],
            "state": "pending_upload",
            "purpose": "home_player_audio",
            "media_type": "audio",
            "owner_user_id": session["owner_user_id"],
            "original_object_path": "media/source-object/source",
        },
        media_asset_id=str(session["media_asset_id"]),
        upload_session_id=str(session["id"]),
        owner_user_id=str(session["owner_user_id"]),
    )

    assert response["asset_state"] == "uploaded"
    assert reconstructed["total_bytes"] == 4


def test_media_upload_session_repository_and_spool_contracts_exist() -> None:
    repo = _required_module("app.repositories.media_upload_sessions")
    service = _required_module("app.services.media_upload_sessions")
    spool = _required_module("app.services.media_upload_spool")

    for name in {
        "create_upload_session",
        "get_upload_session_for_owner_media_asset",
        "get_active_upload_session_for_owner_media_asset",
        "get_upload_chunk",
        "create_upload_chunk",
        "list_upload_chunks",
        "mark_upload_session_finalized",
        "expire_abandoned_upload_sessions",
    }:
        assert hasattr(repo, name), f"media_upload_sessions repo missing {name}"

    for name in {
        "create_home_player_upload_session",
        "receive_home_player_upload_chunk",
        "get_home_player_upload_session_status",
        "finalize_home_player_upload_session",
        "finalize_active_home_player_upload_session",
        "cleanup_abandoned_upload_sessions",
    }:
        assert hasattr(service, name), f"media_upload_sessions service missing {name}"

    for name in {"write_chunk", "reconstruct_source_object", "delete_session_spool"}:
        assert hasattr(spool, name), f"media_upload_spool service missing {name}"


def test_media_upload_session_service_declares_fail_closed_error_contract() -> None:
    service = _required_module("app.services.media_upload_sessions")

    for name in {
        "UploadSessionNotFoundError",
        "UploadSessionConflictError",
        "UploadChunkConflictError",
        "UploadChunkRangeError",
        "UploadChunkChecksumError",
        "UploadSessionIncompleteError",
        "UploadSourceVerificationError",
    }:
        assert hasattr(service, name), f"media_upload_sessions service missing {name}"


def test_chunk_upload_routes_preserve_media_asset_authority() -> None:
    chunk_source = inspect.getsource(_required_route(UPLOAD_CHUNK_ROUTE).endpoint)
    finalize_source = inspect.getsource(_required_route(FINALIZE_SESSION_ROUTE).endpoint)

    for forbidden in (
        "mark_lesson_media_pipeline_asset_uploaded",
        "mark_media_asset_uploaded",
        "mark_media_asset_ready",
        'target_state="uploaded"',
        "target_state='uploaded'",
        'target_state="ready"',
        "target_state='ready'",
    ):
        assert forbidden not in chunk_source

    for forbidden in (
        "mark_media_asset_ready",
        'target_state="ready"',
        "target_state='ready'",
        'asset_state="ready"',
        "asset_state='ready'",
    ):
        assert forbidden not in finalize_source

    assert "finalize_home_player_upload_session" in finalize_source
