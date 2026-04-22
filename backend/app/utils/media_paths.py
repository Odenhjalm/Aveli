from __future__ import annotations

from pathlib import Path, PurePosixPath
from uuid import uuid4

ALLOWED_UPLOAD_PATH_PREFIXES = (
    "media/source/",
    "media/derived/",
    "courses/",
    "lessons/",
    "home-player/",
)
CANONICAL_MEDIA_ASSET_SOURCE_FAMILY = "media/{media_asset_id}/source"
PROTECTED_STORAGE_OBJECT_NAMES = frozenset(
    {
        "logga.png",
        "logga_small.png",
        "aveli_square_transparent_2048.png",
    }
)
PROTECTED_STORAGE_PATH_PREFIXES = ("home-player/",)


def normalize_media_filename(
    filename: str,
    *,
    fallback: str | None = "media",
) -> str | None:
    candidate = str(filename or "").strip().replace("\\", "/")
    safe_name = PurePosixPath(candidate).name.strip()
    if safe_name:
        return safe_name
    return fallback


def media_filename_suffix(filename: str) -> str:
    normalized = normalize_media_filename(filename, fallback=None) or ""
    return Path(normalized).suffix.lower()


def normalize_object_path(path: str) -> str:
    normalized = str(path or "").strip().replace("\\", "/").lstrip("/")
    if not normalized:
        raise ValueError("storage_path cannot be empty")
    return normalized


def build_media_asset_source_object_path(media_asset_id: str) -> str:
    normalized_media_asset_id = str(media_asset_id or "").strip()
    if not normalized_media_asset_id:
        raise ValueError("media_asset_id cannot be empty")
    return (Path("media") / normalized_media_asset_id / "source").as_posix()


def build_media_asset_playback_object_path(media_asset_id: str, *, ext: str) -> str:
    normalized_media_asset_id = str(media_asset_id or "").strip()
    normalized_ext = str(ext or "").strip().lstrip(".")
    if not normalized_media_asset_id:
        raise ValueError("media_asset_id cannot be empty")
    if not normalized_ext:
        raise ValueError("playback extension cannot be empty")
    return (
        Path("media") / normalized_media_asset_id / f"playback.{normalized_ext}"
    ).as_posix()


def is_canonical_media_asset_source_object_path(path: str) -> bool:
    try:
        normalized = normalize_object_path(path)
    except ValueError:
        return False
    parts = PurePosixPath(normalized).parts
    return len(parts) == 3 and parts[0] == "media" and bool(parts[1].strip()) and parts[2] == "source"


def is_canonical_media_asset_source_for_id(
    path: str | None,
    media_asset_id: str | None,
) -> bool:
    normalized_media_asset_id = str(media_asset_id or "").strip()
    if not normalized_media_asset_id:
        return False
    try:
        return normalize_object_path(str(path or "")) == build_media_asset_source_object_path(
            normalized_media_asset_id
        )
    except ValueError:
        return False


def is_allowed_upload_object_path(path: str) -> bool:
    try:
        normalized = normalize_object_path(path)
    except ValueError:
        return False
    if is_canonical_media_asset_source_object_path(normalized):
        return True
    return any(normalized.startswith(prefix) for prefix in ALLOWED_UPLOAD_PATH_PREFIXES)


def is_protected_storage_path(path: str) -> bool:
    try:
        normalized = normalize_object_path(path)
    except ValueError:
        return False
    lower_name = Path(normalized).name.lower()
    if lower_name in PROTECTED_STORAGE_OBJECT_NAMES:
        return True
    return any(
        normalized.startswith(prefix) for prefix in PROTECTED_STORAGE_PATH_PREFIXES
    )


def validate_new_upload_object_path(path: str) -> str:
    normalized = normalize_object_path(path)
    if not is_allowed_upload_object_path(normalized):
        raise ValueError(
            "storage_path must start with one of: "
            + ", ".join((CANONICAL_MEDIA_ASSET_SOURCE_FAMILY,) + ALLOWED_UPLOAD_PATH_PREFIXES)
        )
    return normalized


def build_lesson_audio_source_object_path(
    course_id: str,
    lesson_id: str,
    filename: str,
) -> str:
    safe_name = normalize_media_filename(filename) or "media"
    path = (
        Path("media")
        / "source"
        / "audio"
        / "courses"
        / course_id
        / "lessons"
        / lesson_id
        / safe_name
    )
    return path.as_posix()


def build_home_player_audio_source_object_path(
    user_id: str,
    filename: str,
) -> str:
    safe_name = normalize_media_filename(filename) or "media"
    path = Path("media") / "source" / "audio" / "home-player" / user_id / safe_name
    return path.as_posix()


def build_profile_avatar_source_object_path(
    user_id: str,
    filename: str,
) -> str:
    safe_name = normalize_media_filename(filename) or "media"
    token = uuid4().hex
    path = (
        Path("media")
        / "source"
        / "profile-avatar"
        / str(user_id)
        / f"{token}_{safe_name}"
    )
    return path.as_posix()


def build_lesson_passthrough_object_path(
    *,
    course_id: str,
    lesson_id: str,
    media_kind: str,
    filename: str,
) -> str:
    safe_name = normalize_media_filename(filename) or "media"
    token = uuid4().hex
    normalized_kind = str(media_kind or "").strip().lower()
    if normalized_kind == "image":
        path = Path("lessons") / lesson_id / "images" / f"{token}_{safe_name}"
        return path.as_posix()

    folder = (
        "documents"
        if normalized_kind in {"document", "pdf"}
        else (normalized_kind or "media")
    )
    path = (
        Path("courses")
        / course_id
        / "lessons"
        / lesson_id
        / folder
        / f"{token}_{safe_name}"
    )
    return path.as_posix()


def normalize_storage_path(bucket: str, path: str) -> str:
    normalized_bucket = str(bucket or "").strip().strip("/")
    normalized_path = normalize_object_path(path)
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
