from __future__ import annotations

from pathlib import Path
from uuid import uuid4


def build_audio_source_object_path(
    resource_prefix: Path,
    filename: str,
) -> str:
    safe_name = Path(filename).name.strip()
    if not safe_name:
        safe_name = "media"
    token = uuid4().hex
    path = Path("media") / "source" / "audio" / resource_prefix / f"{token}_{safe_name}"
    return path.as_posix()


def normalize_storage_path(bucket: str, path: str) -> str:
    normalized_bucket = str(bucket or "").strip().strip("/")
    normalized_path = str(path or "").strip().lstrip("/")
    if not normalized_path:
        raise ValueError("storage_path cannot be empty")
    bucket_prefix = f"{normalized_bucket}/"
    if normalized_bucket and normalized_path.startswith(bucket_prefix):
        raise RuntimeError(
            f"Invalid storage_path contains bucket prefix: {normalized_path}"
        )
    return normalized_path


def storage_path_has_bucket_prefix(bucket: str | None, path: str | None) -> bool:
    normalized_bucket = str(bucket or "").strip().strip("/")
    normalized_path = str(path or "").strip().lstrip("/")
    if not normalized_bucket or not normalized_path:
        return False
    return normalized_path.startswith(f"{normalized_bucket}/")
