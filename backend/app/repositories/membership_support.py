from __future__ import annotations

from dataclasses import dataclass
import hashlib
from typing import Any, Literal

from psycopg import errors
from psycopg.types.json import Jsonb

from ..db import pool


_PAYMENT_EVENT_LOCK_PERSON = b"aveli-payev"
PaymentEventClaimStatus = Literal["claimed", "completed", "processing"]


@dataclass(slots=True)
class PaymentEventClaim:
    event_id: str
    status: PaymentEventClaimStatus
    _conn_context: Any | None = None
    _conn: Any | None = None
    _lock_key: int | None = None
    _released: bool = False

    @property
    def claimed(self) -> bool:
        return self.status == "claimed"

    @property
    def completed(self) -> bool:
        return self.status == "completed"

    @property
    def processing(self) -> bool:
        return self.status == "processing"

    async def release(self) -> None:
        if self._released:
            return
        self._released = True

        conn = self._conn
        conn_context = self._conn_context
        lock_key = self._lock_key
        self._conn = None
        self._conn_context = None
        self._lock_key = None

        try:
            if conn is not None and lock_key is not None:
                await _release_payment_event_lock(conn, lock_key)
        finally:
            if conn_context is not None:
                await conn_context.__aexit__(None, None, None)


def _payment_event_lock_key(event_id: str) -> int:
    digest = hashlib.blake2b(
        event_id.encode("utf-8"),
        digest_size=8,
        person=_PAYMENT_EVENT_LOCK_PERSON,
    ).digest()
    return int.from_bytes(digest, byteorder="big", signed=True)


async def _release_payment_event_lock(conn: Any, lock_key: int) -> None:
    try:
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("SELECT pg_advisory_unlock(%s::bigint)", (lock_key,))
            await cur.fetchone()
        await conn.commit()
    except Exception:
        await conn.rollback()
        raise


async def _release_claim_connection(
    *,
    conn_context: Any,
    conn: Any,
    lock_key: int,
    lock_acquired: bool,
) -> None:
    try:
        if lock_acquired:
            await _release_payment_event_lock(conn, lock_key)
    finally:
        await conn_context.__aexit__(None, None, None)


async def claim_payment_event(event_id: str) -> PaymentEventClaim:
    event_id = event_id.strip()
    if not event_id:
        raise ValueError("payment event id must not be blank")

    conn_context = pool.connection()  # type: ignore[attr-defined]
    conn = await conn_context.__aenter__()
    lock_key = _payment_event_lock_key(event_id)
    lock_acquired = False

    try:
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("SELECT pg_try_advisory_lock(%s::bigint)", (lock_key,))
            lock_row = await cur.fetchone()
            lock_acquired = bool(lock_row and lock_row[0])
            if not lock_acquired:
                await conn.commit()
                await conn_context.__aexit__(None, None, None)
                return PaymentEventClaim(event_id=event_id, status="processing")

            await cur.execute(
                """
                SELECT metadata ->> 'status'
                  FROM app.payment_events
                 WHERE event_id = %s
                """,
                (event_id,),
            )
            existing = await cur.fetchone()
        await conn.commit()
    except errors.UndefinedTable:
        await conn.rollback()
        await _release_claim_connection(
            conn_context=conn_context,
            conn=conn,
            lock_key=lock_key,
            lock_acquired=lock_acquired,
        )
        raise
    except Exception:
        await conn.rollback()
        await _release_claim_connection(
            conn_context=conn_context,
            conn=conn,
            lock_key=lock_key,
            lock_acquired=lock_acquired,
        )
        raise

    if existing is not None:
        existing_status = existing[0]
        status: PaymentEventClaimStatus = (
            "completed" if existing_status == "completed" else "processing"
        )
        claim = PaymentEventClaim(
            event_id=event_id,
            status=status,
            _conn_context=conn_context,
            _conn=conn,
            _lock_key=lock_key,
        )
        await claim.release()
        return PaymentEventClaim(event_id=event_id, status=status)

    return PaymentEventClaim(
        event_id=event_id,
        status="claimed",
        _conn_context=conn_context,
        _conn=conn,
        _lock_key=lock_key,
    )


async def complete_payment_event(
    claim: PaymentEventClaim,
    payload: dict[str, Any],
) -> None:
    if not claim.claimed or claim._conn is None:
        raise RuntimeError("payment event completion requires an active claim")

    try:
        async with claim._conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.payment_events (
                    event_id,
                    payload,
                    metadata,
                    processed_at
                )
                VALUES (%s, %s, %s, now())
                ON CONFLICT (event_id) DO NOTHING
                RETURNING event_id
                """,
                (claim.event_id, Jsonb(payload), Jsonb({"status": "completed"})),
            )
            row = await cur.fetchone()
        if row is None:
            await claim._conn.rollback()
            raise RuntimeError("payment event was completed outside the active claim")
        await claim._conn.commit()
    except errors.UndefinedTable:
        await claim._conn.rollback()
        raise
    except Exception:
        await claim._conn.rollback()
        raise


async def insert_billing_log(
    *,
    user_id: str | None,
    step: str,
    info: dict[str, Any] | None = None,
) -> None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.billing_logs (user_id, step, info, created_at)
                    VALUES (%s, %s, %s, now())
                    """,
                    (user_id, step, Jsonb(info or {})),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                raise
            await conn.commit()


__all__ = [
    "PaymentEventClaim",
    "claim_payment_event",
    "complete_payment_event",
    "insert_billing_log",
]
