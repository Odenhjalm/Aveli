from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, status
from psycopg import errors
from psycopg.rows import dict_row

from ..auth import CurrentUser
from ..db import get_conn, pool
from ..permissions import TeacherUser
from ..schemas.events import (
    EventCreateRequest,
    EventListResponse,
    EventParticipantCreateRequest,
    EventParticipantRecord,
    EventRecord,
    EventStatus,
    EventUpdateRequest,
)
from ..schemas.notifications import (
    NotificationAudienceRecord,
    NotificationListResponse,
    NotificationRecord,
)


router = APIRouter(prefix="/api/events", tags=["events"])

_EVENT_STATUS_RANK: dict[str, int] = {
    "draft": 1,
    "scheduled": 2,
    "live": 3,
    "completed": 4,
    "cancelled": 5,
}


def _is_admin(current: dict) -> bool:
    return bool(current.get("is_admin"))


def _validate_status_transition(old: str, new: str) -> None:
    if old == new:
        return
    if old == "cancelled":
        raise HTTPException(status_code=400, detail="Event status cannot be changed after cancellation")
    if new == "cancelled":
        return
    if old == "completed":
        raise HTTPException(status_code=400, detail="Event status cannot be changed after completion")
    old_rank = _EVENT_STATUS_RANK.get(old)
    new_rank = _EVENT_STATUS_RANK.get(new)
    if old_rank is None or new_rank is None:
        raise HTTPException(status_code=400, detail="Invalid event status transition")
    if new_rank < old_rank:
        raise HTTPException(status_code=400, detail=f"Event status cannot move backwards ({old} → {new})")


async def _has_active_membership(user_id: str) -> bool:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT 1
            FROM app.memberships m
            WHERE m.user_id = %s
              AND m.status = 'active'
              AND (m.end_date IS NULL OR m.end_date > now())
            LIMIT 1
            """,
            (user_id,),
        )
        return (await cur.fetchone()) is not None


async def _get_event_row(event_id: str) -> dict | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT
              id,
              type,
              title,
              description,
              image_id,
              start_at,
              end_at,
              timezone,
              status,
              visibility,
              created_by,
              created_at,
              updated_at
            FROM app.events
            WHERE id = %s
            LIMIT 1
            """,
            (event_id,),
        )
        return await cur.fetchone()


async def _user_is_event_participant(event_id: str, user_id: str) -> bool:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT 1
            FROM app.event_participants ep
            WHERE ep.event_id = %s
              AND ep.user_id = %s
              AND ep.status <> 'cancelled'
            LIMIT 1
            """,
            (event_id, user_id),
        )
        return (await cur.fetchone()) is not None


async def _assert_event_read_access(event: dict, current: dict) -> None:
    current_id = str(current["id"])
    if _is_admin(current) or str(event["created_by"]) == current_id:
        return
    if await _user_is_event_participant(str(event["id"]), current_id):
        return

    if event.get("status") == "draft":
        raise HTTPException(status_code=403, detail="You do not have access to this event")

    visibility = event.get("visibility")
    if visibility == "public":
        return
    if visibility == "members":
        if await _has_active_membership(current_id):
            return
        raise HTTPException(status_code=403, detail="Active membership required for this event")
    raise HTTPException(status_code=403, detail="You do not have access to this event")


@router.post("", response_model=EventRecord, status_code=status.HTTP_201_CREATED)
async def create_event(payload: EventCreateRequest, current: TeacherUser) -> EventRecord:
    title = payload.title.strip()
    description = payload.description.strip() if payload.description else None
    timezone_name = payload.timezone.strip()
    if not title:
        raise HTTPException(status_code=400, detail="title must not be empty")
    if not timezone_name:
        raise HTTPException(status_code=400, detail="timezone must not be empty")

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.events (
                      type,
                      title,
                      description,
                      image_id,
                      start_at,
                      end_at,
                      timezone,
                      status,
                      visibility,
                      created_by
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    RETURNING
                      id,
                      type,
                      title,
                      description,
                      image_id,
                      start_at,
                      end_at,
                      timezone,
                      status,
                      visibility,
                      created_by,
                      created_at,
                      updated_at
                    """,
                    (
                        payload.type.value,
                        title,
                        description,
                        str(payload.image_id) if payload.image_id else None,
                        payload.start_at,
                        payload.end_at,
                        timezone_name,
                        payload.status.value,
                        payload.visibility.value,
                        str(current["id"]),
                    ),
                )
                event_row = await cur.fetchone()
                if not event_row:
                    raise HTTPException(status_code=500, detail="Failed to create event")

                await cur.execute(
                    """
                    INSERT INTO app.event_participants (event_id, user_id, role, status, registered_at)
                    VALUES (%s, %s, 'host', 'registered', now())
                    ON CONFLICT (event_id, user_id) DO NOTHING
                    """,
                    (str(event_row["id"]), str(current["id"])),
                )

                await conn.commit()
            except errors.CheckViolation as exc:
                await conn.rollback()
                raise HTTPException(status_code=400, detail=str(exc)) from exc
            except Exception:
                await conn.rollback()
                raise

    return EventRecord(**dict(event_row))


@router.get("", response_model=EventListResponse)
async def list_events(
    current: CurrentUser,
    from_time: datetime | None = Query(
        None,
        description="Return events ending at/after this timestamp",
    ),
    to_time: datetime | None = Query(
        None,
        description="Return events starting at/before this timestamp",
    ),
    type: str | None = Query(None, description="Filter by event type"),
    status_value: EventStatus | None = Query(None, alias="status", description="Filter by event status"),
    limit: int = Query(50, ge=1, le=200),
) -> EventListResponse:
    user_id = str(current["id"])
    is_admin = _is_admin(current)

    conditions: list[str] = [
        """
        (
          e.created_by = %(user_id)s
          OR %(is_admin)s
          OR ep.id IS NOT NULL
          OR (
            e.status <> 'draft'
            AND (
              e.visibility = 'public'
              OR (
                e.visibility = 'members'
                AND EXISTS (
                  SELECT 1
                  FROM app.memberships m
                  WHERE m.user_id = %(user_id)s
                    AND m.status = 'active'
                    AND (m.end_date IS NULL OR m.end_date > now())
                )
              )
            )
          )
        )
        """
    ]
    params: dict[str, object] = {
        "user_id": user_id,
        "is_admin": is_admin,
        "limit": limit,
    }

    if from_time is not None:
        if from_time.tzinfo is None:
            raise HTTPException(status_code=400, detail="from_time must include timezone")
        conditions.append("e.end_at >= %(from_time)s")
        params["from_time"] = from_time

    if to_time is not None:
        if to_time.tzinfo is None:
            raise HTTPException(status_code=400, detail="to_time must include timezone")
        conditions.append("e.start_at <= %(to_time)s")
        params["to_time"] = to_time

    if type is not None:
        if not type.strip():
            raise HTTPException(status_code=400, detail="type must not be empty")
        conditions.append("e.type = %(type)s::app.event_type")
        params["type"] = type.strip()

    if status_value is not None:
        conditions.append("e.status = %(status)s::app.event_status")
        params["status"] = status_value.value

    where_clause = " AND ".join(f"({c.strip()})" for c in conditions)
    query = f"""
        SELECT
          e.id,
          e.type,
          e.title,
          e.description,
          e.image_id,
          e.start_at,
          e.end_at,
          e.timezone,
          e.status,
          e.visibility,
          e.created_by,
          e.created_at,
          e.updated_at
        FROM app.events e
        LEFT JOIN app.event_participants ep
          ON ep.event_id = e.id
         AND ep.user_id = %(user_id)s
         AND ep.status <> 'cancelled'
        WHERE {where_clause}
        ORDER BY e.start_at ASC
        LIMIT %(limit)s
    """
    async with get_conn() as cur:
        try:
            await cur.execute(query, params)
            rows = await cur.fetchall()
        except errors.InvalidTextRepresentation as exc:
            raise HTTPException(status_code=400, detail="Invalid event type/status filter") from exc
    items = [EventRecord(**dict(row)) for row in (rows or [])]
    return EventListResponse(items=items)


@router.get("/{event_id}", response_model=EventRecord)
async def get_event(event_id: UUID, current: CurrentUser) -> EventRecord:
    row = await _get_event_row(str(event_id))
    if not row:
        raise HTTPException(status_code=404, detail="Event not found")
    await _assert_event_read_access(dict(row), current)
    return EventRecord(**dict(row))


@router.patch("/{event_id}", response_model=EventRecord)
async def update_event(
    event_id: UUID,
    payload: EventUpdateRequest,
    current: TeacherUser,
) -> EventRecord:
    event = await _get_event_row(str(event_id))
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    if not _is_admin(current) and str(event["created_by"]) != str(current["id"]):
        raise HTTPException(status_code=403, detail="Only the event creator may update this event")

    updates: dict[str, object] = {}
    if payload.type is not None:
        updates["type"] = payload.type.value
    if payload.title is not None:
        title = payload.title.strip()
        if not title:
            raise HTTPException(status_code=400, detail="title must not be empty")
        updates["title"] = title
    if payload.description is not None:
        updates["description"] = payload.description.strip() if payload.description else None
    if payload.image_id is not None:
        updates["image_id"] = str(payload.image_id)
    if payload.timezone is not None:
        timezone_name = payload.timezone.strip()
        if not timezone_name:
            raise HTTPException(status_code=400, detail="timezone must not be empty")
        updates["timezone"] = timezone_name
    if payload.visibility is not None:
        updates["visibility"] = payload.visibility.value
    if payload.start_at is not None:
        updates["start_at"] = payload.start_at
    if payload.end_at is not None:
        updates["end_at"] = payload.end_at
    if payload.status is not None:
        _validate_status_transition(str(event["status"]), payload.status.value)
        updates["status"] = payload.status.value

    if not updates:
        return EventRecord(**dict(event))

    new_start = payload.start_at or event["start_at"]
    new_end = payload.end_at or event["end_at"]
    if new_end <= new_start:
        raise HTTPException(status_code=400, detail="end_at must be after start_at")

    assignments = ", ".join(f"{key} = %({key})s" for key in updates.keys())
    updates["event_id"] = str(event_id)

    query = f"""
        UPDATE app.events
        SET {assignments},
            updated_at = now()
        WHERE id = %(event_id)s
        RETURNING
          id,
          type,
          title,
          description,
          image_id,
          start_at,
          end_at,
          timezone,
          status,
          visibility,
          created_by,
          created_at,
          updated_at
    """
    async with get_conn() as cur:
        try:
            await cur.execute(query, updates)
            row = await cur.fetchone()
        except errors.CheckViolation as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except errors.RaiseException as exc:
            detail = exc.diag.message_primary if getattr(exc, "diag", None) else str(exc)
            raise HTTPException(status_code=400, detail=detail) from exc
    if not row:
        raise HTTPException(status_code=404, detail="Event not found")
    return EventRecord(**dict(row))


@router.post(
    "/{event_id}/participants",
    response_model=EventParticipantRecord,
    status_code=status.HTTP_201_CREATED,
)
async def register_participant(
    event_id: UUID,
    payload: EventParticipantCreateRequest,
    current: CurrentUser,
) -> EventParticipantRecord:
    event = await _get_event_row(str(event_id))
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    current_id = str(current["id"])
    is_owner = str(event["created_by"]) == current_id
    is_admin = _is_admin(current)

    target_user_id = str(payload.user_id) if payload.user_id else current_id
    if target_user_id != current_id and not (is_owner or is_admin):
        raise HTTPException(status_code=403, detail="Only the event creator may register other users")

    if payload.role.value == "host" and not (is_owner or is_admin):
        raise HTTPException(status_code=403, detail="Only the event creator may assign host role")

    if event["status"] in {"cancelled", "completed"}:
        raise HTTPException(status_code=400, detail="Event is closed")

    if not (is_owner or is_admin) and target_user_id == current_id:
        if event["status"] == "draft":
            raise HTTPException(status_code=403, detail="Event is not published")
        if event["visibility"] == "invited":
            raise HTTPException(status_code=403, detail="This event requires an invitation")
        if event["visibility"] == "members":
            if not await _has_active_membership(current_id):
                raise HTTPException(status_code=403, detail="Active membership required for this event")

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.event_participants (event_id, user_id, role, status, registered_at)
                    VALUES (%s, %s, %s, 'registered', now())
                    ON CONFLICT (event_id, user_id) DO NOTHING
                    RETURNING id, event_id, user_id, role, status, registered_at
                    """,
                    (str(event_id), target_user_id, payload.role.value),
                )
                row = await cur.fetchone()
                if row:
                    await conn.commit()
                    return EventParticipantRecord(**dict(row))

                await cur.execute(
                    """
                    SELECT id, event_id, user_id, role, status, registered_at
                    FROM app.event_participants
                    WHERE event_id = %s AND user_id = %s
                    LIMIT 1
                    """,
                    (str(event_id), target_user_id),
                )
                existing = await cur.fetchone()
                if not existing:
                    await conn.rollback()
                    raise HTTPException(status_code=500, detail="Failed to register participant")

                existing_role = str(existing["role"])
                existing_status = str(existing["status"])
                role_to_set = existing_role
                if is_owner or is_admin:
                    role_to_set = payload.role.value

                if existing_status == "cancelled" or (role_to_set != existing_role and (is_owner or is_admin)):
                    await cur.execute(
                        """
                        UPDATE app.event_participants
                        SET status = 'registered',
                            role = %s,
                            registered_at = now()
                        WHERE id = %s
                        RETURNING id, event_id, user_id, role, status, registered_at
                        """,
                        (role_to_set, str(existing["id"])),
                    )
                    updated = await cur.fetchone()
                    await conn.commit()
                    if not updated:
                        raise HTTPException(status_code=500, detail="Failed to update registration")
                    return EventParticipantRecord(**dict(updated))

                await conn.commit()
                return EventParticipantRecord(**dict(existing))
            except HTTPException:
                await conn.rollback()
                raise
            except Exception:
                await conn.rollback()
                raise


@router.get("/{event_id}/notifications", response_model=NotificationListResponse)
async def list_event_notifications(event_id: UUID, current: TeacherUser) -> NotificationListResponse:
    event = await _get_event_row(str(event_id))
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    if not _is_admin(current) and str(event["created_by"]) != str(current["id"]):
        raise HTTPException(status_code=403, detail="Only the event creator may view notifications for this event")

    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT DISTINCT
              n.id,
              n.type,
              n.channel,
              n.title,
              n.body,
              n.send_at,
              n.created_by,
              n.status,
              n.created_at,
              COALESCE(delivery_counts.recipient_count, 0) AS recipient_count
            FROM app.notification_campaigns n
            JOIN app.notification_audiences a ON a.notification_id = n.id
            LEFT JOIN LATERAL (
              SELECT COUNT(*)::int AS recipient_count
              FROM app.notification_deliveries d
              WHERE d.notification_id = n.id
            ) delivery_counts ON true
            WHERE a.audience_type = 'event_participants'
              AND a.event_id = %s
            ORDER BY n.created_at DESC
            """,
            (str(event_id),),
        )
        campaigns = await cur.fetchall()

    if not campaigns:
        return NotificationListResponse(items=[])

    notification_ids = [str(row["id"]) for row in campaigns]
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, notification_id, audience_type, event_id, course_id
            FROM app.notification_audiences
            WHERE notification_id = ANY(%s::uuid[])
            ORDER BY notification_id, id
            """,
            (notification_ids,),
        )
        audience_rows = await cur.fetchall()

    audiences_by_notification: dict[str, list[NotificationAudienceRecord]] = {}
    for row in audience_rows or []:
        key = str(row["notification_id"])
        audiences_by_notification.setdefault(key, []).append(
            NotificationAudienceRecord(**dict(row))
        )

    items: list[NotificationRecord] = []
    for row in campaigns:
        data = dict(row)
        notif_id = str(data["id"])
        data["audiences"] = audiences_by_notification.get(notif_id, [])
        items.append(NotificationRecord(**data))

    return NotificationListResponse(items=items)
