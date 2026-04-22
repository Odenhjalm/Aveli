from pathlib import Path

from app import db


BACKEND_DIR = Path(__file__).resolve().parents[1]
CUSTOM_DRIP_SLOT_PATHS = (
    BACKEND_DIR / "supabase" / "baseline_v2_slots" / "V2_0025_custom_drip_substrate.sql",
    BACKEND_DIR
    / "supabase"
    / "baseline_v2_slots"
    / "V2_0026_custom_drip_runtime_alignment.sql",
)


async def ensure_custom_drip_schema() -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            for path in CUSTOM_DRIP_SLOT_PATHS:
                await cur.execute(path.read_text(encoding="utf-8"))
        await conn.commit()
