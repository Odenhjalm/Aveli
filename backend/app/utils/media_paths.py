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


def is_allowed_upload_object_path(path: str) -> bool:
    try:
        normalized = normalize_object_path(path)
    except ValueError:
        return False
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
            + ", ".join(ALLOWED_UPLOAD_PATH_PREFIXES)
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
