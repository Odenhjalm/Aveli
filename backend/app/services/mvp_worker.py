from __future__ import annotations

import asyncio
import logging

from . import course_drip_worker, media_transcode_worker

logger = logging.getLogger(__name__)


async def _run_worker_forever() -> None:
    from ..db import pool

    await pool.open(wait=True)
    try:
        await media_transcode_worker.start_worker()
        await course_drip_worker.start_worker()
        logger.info("MVP worker runtime started")
        while True:
            await asyncio.sleep(3600)
    finally:
        await course_drip_worker.stop_worker()
        await media_transcode_worker.stop_worker()
        await pool.close()


if __name__ == "__main__":
    from ..logging_utils import setup_logging

    setup_logging()
    try:
        asyncio.run(_run_worker_forever())
    except KeyboardInterrupt:
        logger.info("MVP worker runtime stopped")
