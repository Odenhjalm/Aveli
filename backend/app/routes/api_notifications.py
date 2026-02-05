from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, status
from psycopg import errors
from psycopg.rows import dict_row

from ..db import get_conn, pool
from ..permissions import TeacherUser
from ..schemas.notifications import (
    NotificationAudienceCreate,
    NotificationAudienceType,
    NotificationAudienceRecord,
    NotificationCreateRequest,
    NotificationCreateResponse,
    NotificationRecord,
)


router = APIRouter(prefix="/api/notifications", tags=["notifications"])


def _is_admin(current: dict) -> bool:
    return bool(current.get("is_admin"))


async def _event_owner(event_id: str) -> str | None:
    async with get_conn() as cur:
        await cur.execute("SELECT created_by FROM app.events WHERE id = %s LIMIT 1", (event_id,))
        row = await cur.fetchone()
        return str(row["created_by"]) if row else None


async def _course_owner(course_id: str) -> str | None:
    async with get_conn() as cur:
        await cur.execute("SELECT created_by FROM app.courses WHERE id = %s LIMIT 1", (course_id,))
        row = await cur.fetchone()
        if not row:
            return None
        created_by = row.get("created_by")
        return str(created_by) if created_by else None


async def _assert_audience_permissions(audiences: list[NotificationAudienceCreate], current: dict) -> None:
    user_id = str(current["id"])
    is_admin = _is_admin(current)

    event_ids: set[str] = set()
    course_ids: set[str] = set()
    has_all_members = False

    for aud in audiences:
        if aud.audience_type == NotificationAudienceType.all_members:
            has_all_members = True
        elif aud.audience_type == NotificationAudienceType.event_participants and aud.event_id:
            event_ids.add(str(aud.event_id))
        elif aud.audience_type in {NotificationAudienceType.course_participants, NotificationAudienceType.course_members} and aud.course_id:
            course_ids.add(str(aud.course_id))

    if has_all_members and not is_admin:
        raise HTTPException(status_code=403, detail="Only admins may target all_members")

    for eid in sorted(event_ids):
        owner = await _event_owner(eid)
        if owner is None:
            raise HTTPException(status_code=404, detail=f"Event not found: {eid}")
        if not (is_admin or owner == user_id):
            raise HTTPException(status_code=403, detail="You may only notify participants of your own events")

    for cid in sorted(course_ids):
        owner = await _course_owner(cid)
        if owner is None:
            raise HTTPException(status_code=404, detail=f"Course not found: {cid}")
        if not (is_admin or owner == user_id):
            raise HTTPException(status_code=403, detail="You may only notify participants of your own courses")


async def _resolve_recipients(audiences: list[NotificationAudienceCreate]) -> set[str]:
    event_ids: set[str] = set()
    course_participant_ids: set[str] = set()
    course_member_ids: set[str] = set()
    wants_all_members = False

    for aud in audiences:
        if aud.audience_type == NotificationAudienceType.all_members:
            wants_all_members = True
        elif aud.audience_type == NotificationAudienceType.event_participants and aud.event_id:
            event_ids.add(str(aud.event_id))
        elif aud.audience_type == NotificationAudienceType.course_participants and aud.course_id:
            course_participant_ids.add(str(aud.course_id))
        elif aud.audience_type == NotificationAudienceType.course_members and aud.course_id:
            course_member_ids.add(str(aud.course_id))

    recipients: set[str] = set()
    async with get_conn() as cur:
        if wants_all_members:
            await cur.execute(
                """
                SELECT DISTINCT p.user_id
                FROM app.memberships m
                JOIN app.profiles p ON p.user_id = m.user_id
                WHERE m.status = 'active'
                  AND (m.end_date IS NULL OR m.end_date > now())
                """,
            )
            rows = await cur.fetchall()
            recipients.update(str(r["user_id"]) for r in (rows or []))

        if event_ids:
            await cur.execute(
                """
                SELECT DISTINCT ep.user_id
                FROM app.event_participants ep
                WHERE ep.event_id = ANY(%s::uuid[])
                  AND ep.status <> 'cancelled'
                """,
                (sorted(event_ids),),
            )
            rows = await cur.fetchall()
            recipients.update(str(r["user_id"]) for r in (rows or []))

        if course_participant_ids:
            await cur.execute(
                """
                SELECT DISTINCT e.user_id
                FROM app.enrollments e
                WHERE e.course_id = ANY(%s::uuid[])
                  AND e.status = 'active'
                """,
                (sorted(course_participant_ids),),
            )
            rows = await cur.fetchall()
            recipients.update(str(r["user_id"]) for r in (rows or []))

        if course_member_ids:
            await cur.execute(
                """
                SELECT DISTINCT e.user_id
                FROM app.enrollments e
                WHERE e.course_id = ANY(%s::uuid[])
                  AND e.status = 'active'
                  AND e.source = 'membership'
                """,
                (sorted(course_member_ids),),
            )
            rows = await cur.fetchall()
            recipients.update(str(r["user_id"]) for r in (rows or []))

    return recipients


@router.post("", response_model=NotificationCreateResponse, status_code=status.HTTP_201_CREATED)
async def create_notification(payload: NotificationCreateRequest, current: TeacherUser) -> NotificationCreateResponse:
    title = payload.title.strip()
    body = payload.body.strip()
    if not title:
        raise HTTPException(status_code=400, detail="title must not be empty")
    if not body:
        raise HTTPException(status_code=400, detail="body must not be empty")
    if not payload.audiences:
        raise HTTPException(status_code=400, detail="At least one audience is required")

    await _assert_audience_permissions(payload.audiences, current)
    recipients = await _resolve_recipients(payload.audiences)
    if not recipients:
        raise HTTPException(status_code=400, detail="Audience resolved to 0 recipients")

    now = datetime.now(timezone.utc)
    send_at = payload.send_at.astimezone(timezone.utc) if payload.send_at else now
    should_send_now = send_at <= now

    campaign_status = "sent" if should_send_now else "pending"
    delivery_status = "sent" if should_send_now else "pending"
    sent_at = now if should_send_now else None

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.notification_campaigns (
                      type,
                      channel,
                      title,
                      body,
                      send_at,
                      created_by,
                      status
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    RETURNING
                      id,
                      type,
                      channel,
                      title,
                      body,
                      send_at,
                      created_by,
                      status,
                      created_at
                    """,
                    (
                        payload.type.value,
                        payload.channel.value,
                        title,
                        body,
                        send_at,
                        str(current["id"]),
                        campaign_status,
                    ),
                )
                campaign = await cur.fetchone()
                if not campaign:
                    raise HTTPException(status_code=500, detail="Failed to create notification")

                audience_records: list[NotificationAudienceRecord] = []
                for aud in payload.audiences:
                    await cur.execute(
                        """
                        INSERT INTO app.notification_audiences (
                          notification_id,
                          audience_type,
                          event_id,
                          course_id
                        )
                        VALUES (%s, %s, %s, %s)
                        RETURNING id, notification_id, audience_type, event_id, course_id
                        """,
                        (
                            str(campaign["id"]),
                            aud.audience_type.value,
                            str(aud.event_id) if aud.event_id else None,
                            str(aud.course_id) if aud.course_id else None,
                        ),
                    )
                    aud_row = await cur.fetchone()
                    if not aud_row:
                        raise HTTPException(status_code=500, detail="Failed to create notification audience")
                    audience_records.append(NotificationAudienceRecord(**dict(aud_row)))

                await cur.execute(
                    """
                    INSERT INTO app.notification_deliveries (
                      notification_id,
                      user_id,
                      channel,
                      status,
                      sent_at,
                      created_at
                    )
                    SELECT
                      %s,
                      u.user_id,
                      %s,
                      %s,
                      %s,
                      now()
                    FROM unnest(%s::uuid[]) AS u(user_id)
                    ON CONFLICT (notification_id, user_id, channel) DO NOTHING
                    """,
                    (
                        str(campaign["id"]),
                        payload.channel.value,
                        delivery_status,
                        sent_at,
                        sorted(recipients),
                    ),
                )

                await conn.commit()
            except errors.CheckViolation as exc:
                await conn.rollback()
                raise HTTPException(status_code=400, detail=str(exc)) from exc
            except errors.ForeignKeyViolation as exc:
                await conn.rollback()
                raise HTTPException(status_code=400, detail=str(exc)) from exc
            except HTTPException:
                await conn.rollback()
                raise
            except Exception:
                await conn.rollback()
                raise

    record = NotificationRecord(
        **dict(campaign),
        audiences=audience_records,
        recipient_count=len(recipients),
    )
    return NotificationCreateResponse(notification=record)
