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

