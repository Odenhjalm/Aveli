#!/usr/bin/env python3
"""Generate Supabase Storage presigned uploads using backend config/settings.

Example:
    scripts/presign_upload.py --bucket course-media --path courses/demo/lesson-1.wav \\
        --content-type audio/wav --upsert
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
BACKEND_DIR = ROOT_DIR / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.services.storage_service import (  # noqa: E402  (path hack above)
    StorageService,
    StorageServiceError,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Request presigned upload URL from Supabase Storage.")
    parser.add_argument(
        "--bucket",
        default="course-media",
        help="Storage bucket to target (default: %(default)s).",
    )
    parser.add_argument(
        "--path",
        required=True,
        help="Object path inside the bucket (e.g. courses/demo/lesson-1.wav).",
    )
    parser.add_argument(
        "--content-type",
        default="application/octet-stream",
        help="Content-Type header to attach to the upload (default: %(default)s).",
    )
    parser.add_argument(
        "--upsert",
        action="store_true",
        help="Allow overwriting an existing object.",
    )
    parser.add_argument(
        "--cache-seconds",
        type=int,
        default=3600,
        help="Cache-Control max-age for the uploaded object (default: %(default)s).",
    )
    return parser.parse_args()


async def main() -> None:
    args = parse_args()
    service = StorageService(bucket=args.bucket)
    try:
        presigned = await service.create_upload_url(
            args.path,
            content_type=args.content_type,
            upsert=args.upsert,
            cache_seconds=args.cache_seconds,
        )
    except StorageServiceError as exc:
        print(f"Failed to create upload URL: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc

    payload = {
        "bucket": args.bucket,
        "path": presigned.path,
        "url": presigned.url,
        "expires_in": presigned.expires_in,
        "headers": dict(presigned.headers),
    }
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
