from datetime import datetime, timezone
from typing import Any, Optional

from psycopg.types.json import Jsonb

from ..db import get_conn


_SEMINAR_ATTENDEE_BASE = """
    select
        sa.seminar_id,
        sa.user_id,
        sa.role,
        sa.invite_status,
        sa.joined_at,
        sa.left_at,
        sa.livekit_identity,
        sa.livekit_participant_sid,
        sa.created_at,
        p.display_name as profile_display_name,
        p.email as profile_email,
        coalesce(host_courses.course_titles, ARRAY[]::text[]) as host_course_titles
    from app.seminar_attendees sa
    join app.seminars s on s.id = sa.seminar_id
    left join app.profiles p on p.user_id = sa.user_id
    left join lateral (
        select array_agg(c.title order by c.title) as course_titles
        from app.enrollments e
        join app.courses c on c.id = e.course_id
        where e.user_id = sa.user_id
          and c.created_by = s.host_id
    ) as host_courses on true
    where sa.seminar_id = %s
"""


def _normalize_metadata(metadata: Any) -> dict[str, Any]:
    if isinstance(metadata, Jsonb):
        metadata = metadata.obj
    if metadata is None:
        return {}
    if isinstance(metadata, dict):
        return metadata
    try:
        return dict(metadata)
    except (TypeError, ValueError):
        return {}


async def get_seminar_attendee(seminar_id: str, user_id: str) -> Optional[dict]:
    query = _SEMINAR_ATTENDEE_BASE + """
        and sa.user_id = %s
        limit 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (seminar_id, user_id))
        return await cur.fetchone()


async def get_seminar(seminar_id: str) -> dict | None:
    query = """
        select s.id,
               s.host_id,
               s.title,
               s.description,
               s.status,
               s.scheduled_at,
               s.duration_minutes,
               s.livekit_room,
               s.livekit_metadata,
               s.created_at,
               s.updated_at,
               p.display_name as host_display_name
        from app.seminars s
        left join app.profiles p on p.user_id = s.host_id
        where s.id = %s
        limit 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (seminar_id,))
        return await cur.fetchone()


async def list_host_seminars(host_id: str) -> list[dict]:
    query = """
        select s.id,
               s.host_id,
               s.title,
               s.description,
               s.status,
               s.scheduled_at,
               s.duration_minutes,
               s.livekit_room,
               s.livekit_metadata,
               s.created_at,
               s.updated_at,
               p.display_name as host_display_name
        from app.seminars s
        left join app.profiles p on p.user_id = s.host_id
        where s.host_id = %s
        order by s.scheduled_at nulls last, s.created_at desc
    """
    async with get_conn() as cur:
        await cur.execute(query, (host_id,))
        return await cur.fetchall()


async def list_public_seminars(limit: int = 20) -> list[dict]:
    query = """
        select s.id,
               s.host_id,
               s.title,
               s.description,
               s.status,
               s.scheduled_at,
               s.duration_minutes,
               s.livekit_room,
               s.created_at,
               s.updated_at,
               p.display_name as host_display_name
        from app.seminars s
        left join app.profiles p on p.user_id = s.host_id
        where s.status in ('scheduled', 'live')
        order by s.scheduled_at nulls last, s.created_at desc
        limit %s
    """
    async with get_conn() as cur:
        await cur.execute(query, (limit,))
        return await cur.fetchall()


async def create_seminar(
    *,
    host_id: str,
    title: str,
    description: Optional[str],
    scheduled_at: Optional[str],
    duration_minutes: Optional[int],
) -> dict:
    query = """
        insert into app.seminars (
            host_id,
            title,
            description,
            scheduled_at,
            duration_minutes,
            status
        )
        values (%s, %s, %s, %s, %s, 'draft')
        returning id,
                  host_id,
                  title,
                  description,
                  status,
                  scheduled_at,
                  duration_minutes,
                  livekit_room,
                  livekit_metadata,
                  created_at,
                  updated_at
    """
    async with get_conn() as cur:
        await cur.execute(
            query,
            (host_id, title, description, scheduled_at, duration_minutes),
        )
        return await cur.fetchone()


async def update_seminar(
    *,
    seminar_id: str,
    host_id: str,
    fields: dict[str, Any],
) -> Optional[dict]:
    if not fields:
        return await get_seminar(seminar_id)

    assignments = ", ".join(f"{key} = %({key})s" for key in fields.keys())
    fields.update({"seminar_id": seminar_id, "host_id": host_id})
    query = f"""
        update app.seminars
        set {assignments},
            updated_at = now()
        where id = %(seminar_id)s
          and host_id = %(host_id)s
        returning id,
                  host_id,
                  title,
                  description,
                  status,
                  scheduled_at,
                  duration_minutes,
                  livekit_room,
                  livekit_metadata,
                  created_at,
                  updated_at
    """
    async with get_conn() as cur:
        await cur.execute(query, fields)
        return await cur.fetchone()


async def set_seminar_status(
    *,
    seminar_id: str,
    host_id: str,
    status: str,
) -> Optional[dict]:
    query = """
        update app.seminars
        set status = %s,
            updated_at = now()
        where id = %s
          and host_id = %s
        returning id,
                  host_id,
                  title,
                  description,
                  status,
                  scheduled_at,
                  duration_minutes,
                  livekit_room,
                  livekit_metadata,
                  created_at,
                  updated_at
    """
    async with get_conn() as cur:
        await cur.execute(query, (status, seminar_id, host_id))
        return await cur.fetchone()


async def create_seminar_session(
    *,
    seminar_id: str,
    status: str,
    scheduled_at: Optional[str],
    livekit_room: Optional[str],
    livekit_sid: Optional[str],
    metadata: Optional[dict[str, Any]] = None,
) -> dict:
    query = """
        insert into app.seminar_sessions (
            seminar_id,
            status,
            scheduled_at,
            livekit_room,
            livekit_sid,
            metadata
        )
        values (%s, %s, %s, %s, %s, %s)
        returning id,
                  seminar_id,
                  status,
                  scheduled_at,
                  started_at,
                  ended_at,
                  livekit_room,
                  livekit_sid,
                  metadata,
                  created_at,
                  updated_at
    """
    async with get_conn() as cur:
        await cur.execute(
            query,
            (
                seminar_id,
                status,
                scheduled_at,
                livekit_room,
                livekit_sid,
                Jsonb(_normalize_metadata(metadata)),
            ),
        )
        return await cur.fetchone()


async def update_seminar_session(
    *,
    session_id: str,
    fields: dict[str, Any],
) -> Optional[dict]:
    if not fields:
        return await get_seminar_session(session_id)

    assignments = ", ".join(f"{key} = %({key})s" for key in fields.keys())
    if "metadata" in fields and fields["metadata"] is not None:
        fields = {
            **fields,
            "metadata": Jsonb(_normalize_metadata(fields["metadata"])),
        }
    fields.update({"session_id": session_id})
    query = f"""
        update app.seminar_sessions
        set {assignments},
            updated_at = now()
        where id = %(session_id)s
        returning id,
                  seminar_id,
                  status,
                  scheduled_at,
                  started_at,
                  ended_at,
                  livekit_room,
                  livekit_sid,
                  metadata,
                  created_at,
                  updated_at
    """
    async with get_conn() as cur:
        await cur.execute(query, fields)
        return await cur.fetchone()


async def get_seminar_session(session_id: str) -> Optional[dict]:
    query = """
        select id,
               seminar_id,
               status,
               scheduled_at,
               started_at,
               ended_at,
               livekit_room,
               livekit_sid,
               metadata,
               created_at,
               updated_at
        from app.seminar_sessions
        where id = %s
        limit 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (session_id,))
        return await cur.fetchone()


async def get_latest_session(seminar_id: str) -> Optional[dict]:
    query = """
        select id,
               seminar_id,
               status,
               scheduled_at,
               started_at,
               ended_at,
               livekit_room,
               livekit_sid,
               metadata,
               created_at,
               updated_at
        from app.seminar_sessions
        where seminar_id = %s
        order by created_at desc
        limit 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (seminar_id,))
        return await cur.fetchone()


async def get_session_by_room(room_name: str) -> Optional[dict]:
    query = """
        select id,
               seminar_id,
               status,
               scheduled_at,
               started_at,
               ended_at,
               livekit_room,
               livekit_sid,
               metadata,
               created_at,
               updated_at
        from app.seminar_sessions
        where livekit_room = %s
        order by created_at desc
        limit 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (room_name,))
        return await cur.fetchone()


async def list_seminar_sessions(seminar_id: str) -> list[dict]:
    query = """
        select id,
               seminar_id,
               status,
               scheduled_at,
               started_at,
               ended_at,
               livekit_room,
               livekit_sid,
               metadata,
               created_at,
               updated_at
        from app.seminar_sessions
        where seminar_id = %s
        order by created_at desc
    """
    async with get_conn() as cur:
        await cur.execute(query, (seminar_id,))
        return await cur.fetchall()


async def list_seminar_attendees(seminar_id: str) -> list[dict]:
    query = _SEMINAR_ATTENDEE_BASE + """
        order by sa.created_at asc
    """
    async with get_conn() as cur:
        await cur.execute(query, (seminar_id,))
        return await cur.fetchall()


async def list_seminar_recordings(seminar_id: str) -> list[dict]:
    query = """
        select id,
               seminar_id,
               session_id,
               asset_url,
               status,
               duration_seconds,
               byte_size,
               published,
               metadata,
               created_at,
               updated_at
        from app.seminar_recordings
        where seminar_id = %s
        order by created_at desc
    """
    async with get_conn() as cur:
        await cur.execute(query, (seminar_id,))
        return await cur.fetchall()


async def get_recording_by_asset_url(asset_url: str) -> dict | None:
    query = """
        select id,
               seminar_id,
               asset_url,
               status,
               published,
               metadata,
               created_at,
               updated_at
        from app.seminar_recordings
        where asset_url = %s
        limit 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (asset_url,))
        return await cur.fetchone()


async def register_attendee(
    *,
    seminar_id: str,
    user_id: str,
    role: str = "participant",
    invite_status: str = "accepted",
) -> dict:
    query = """
        insert into app.seminar_attendees (
            seminar_id,
            user_id,
            role,
            invite_status,
            joined_at,
            created_at
        )
        values (%s, %s, %s, %s, null, now())
        on conflict (seminar_id, user_id) do update
        set role = excluded.role,
            invite_status = excluded.invite_status,
            created_at = excluded.created_at
        returning seminar_id,
                  user_id,
                  role,
                  invite_status,
                  joined_at,
                  left_at,
                  livekit_identity,
                  livekit_participant_sid,
                  created_at
    """
    async with get_conn() as cur:
        await cur.execute(query, (seminar_id, user_id, role, invite_status))
    attendee = await get_seminar_attendee(seminar_id, user_id)
    if attendee is None:
        return {
            "seminar_id": seminar_id,
            "user_id": user_id,
            "role": role,
            "invite_status": invite_status,
            "joined_at": None,
            "left_at": None,
            "livekit_identity": None,
            "livekit_participant_sid": None,
            "created_at": datetime.now(timezone.utc),
            "profile_display_name": None,
            "profile_email": None,
            "host_course_titles": [],
        }
    return attendee


async def unregister_attendee(*, seminar_id: str, user_id: str) -> bool:
    query = """
        delete from app.seminar_attendees
        where seminar_id = %s
          and user_id = %s
    """
    async with get_conn() as cur:
        await cur.execute(query, (seminar_id, user_id))
        return cur.rowcount > 0


async def get_user_seminar_role(user_id: str, seminar_id: str) -> Optional[str]:
    seminar = await get_seminar(seminar_id)
    if not seminar:
        return None
    if str(seminar["host_id"]) == str(user_id):
        return "host"

    query = """
        select invite_status
        from app.seminar_attendees
        where seminar_id = %s
          and user_id = %s
        limit 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (seminar_id, user_id))
        row = await cur.fetchone()
    if row:
        status = row["invite_status"]
        if status in ("accepted", "pending"):
            return "participant"
    return None


async def touch_attendee_presence(
    *,
    seminar_id: str,
    user_id: str,
    joined_at: Optional[datetime],
    left_at: Optional[datetime],
    livekit_identity: Optional[str],
    participant_sid: Optional[str],
) -> None:
    query = """
        update app.seminar_attendees
        set joined_at = coalesce(%s, joined_at),
            left_at = coalesce(%s, left_at),
            livekit_identity = coalesce(%s, livekit_identity),
            livekit_participant_sid = coalesce(%s, livekit_participant_sid)
        where seminar_id = %s
          and user_id = %s
    """
    async with get_conn() as cur:
        await cur.execute(
            query,
            (
                joined_at,
                left_at,
                livekit_identity,
                participant_sid,
                seminar_id,
                user_id,
            ),
        )


async def upsert_recording(
    *,
    seminar_id: str,
    session_id: Optional[str],
    asset_url: str,
    status: str,
    duration_seconds: Optional[int],
    byte_size: Optional[int],
    metadata: Optional[dict[str, Any]] = None,
) -> dict:
    query = """
        insert into app.seminar_recordings (
            seminar_id,
            session_id,
            asset_url,
            status,
            duration_seconds,
            byte_size,
            metadata
        )
        values (%s, %s, %s, %s, %s, %s, %s)
        returning id,
                  seminar_id,
                  session_id,
                  asset_url,
                  status,
                  duration_seconds,
                  byte_size,
                  published,
                  metadata,
                  created_at,
                  updated_at
    """
    async with get_conn() as cur:
        await cur.execute(
            query,
            (
                seminar_id,
                session_id,
                asset_url,
                status,
                duration_seconds,
                byte_size,
                Jsonb(metadata or {}),
            ),
        )
        return await cur.fetchone()


async def user_can_access_seminar(user_id: str, seminar_id: str) -> bool:
    role = await get_user_seminar_role(user_id, seminar_id)
    return role is not None


async def user_has_seminar_access(user_id: str, seminar: dict) -> bool:
    metadata_raw = seminar.get("livekit_metadata") or {}
    metadata = metadata_raw if isinstance(metadata_raw, dict) else {}
    if metadata.get("is_free") or metadata.get("free"):
        return True
    if metadata.get("requires_payment") is False:
        return True

    service_id = metadata.get("service_id") or metadata.get("order_service_id")
    seminar_id = str(seminar["id"])

    async with get_conn() as cur:
        if service_id:
            await cur.execute(
                """
                select 1
                from app.orders
                where user_id = %s
                  and status = 'paid'
                  and service_id = %s
                limit 1
                """,
                (user_id, str(service_id)),
            )
            if await cur.fetchone():
                return True

        await cur.execute(
            """
            select 1
            from app.orders
            where user_id = %s
              and status = 'paid'
              and (
                metadata ->> 'seminar_id' = %s
                or metadata -> 'seminar' ->> 'id' = %s
              )
            limit 1
            """,
            (user_id, seminar_id, seminar_id),
        )
        row = await cur.fetchone()

    return row is not None
