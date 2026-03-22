from __future__ import annotations

import logging
import mimetypes
import re
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Iterable, Mapping
from urllib.parse import unquote, urlparse
from uuid import uuid4

from ..config import settings
from ..repositories import courses as courses_repo
from ..repositories import media_assets as media_assets_repo
from ..repositories import storage_objects
from ..services import storage_service
from ..utils import media_paths

logger = logging.getLogger(__name__)

CLASS_ALREADY_CONTROL_PLANE = "already_control_plane"
CLASS_LEGACY_MIGRATABLE = "legacy_migratable"
CLASS_LEGACY_PUBLIC_BUT_NONCANONICAL = "legacy_public_but_noncanonical"
CLASS_LEGACY_UNVERIFIABLE = "legacy_unverifiable"
CLASS_HYBRID_BROKEN = "hybrid_broken"

_ALL_CLASSES = (
    CLASS_ALREADY_CONTROL_PLANE,
    CLASS_LEGACY_MIGRATABLE,
    CLASS_LEGACY_PUBLIC_BUT_NONCANONICAL,
    CLASS_LEGACY_UNVERIFIABLE,
    CLASS_HYBRID_BROKEN,
)

_URL_PATH_PREFIXES = (
    "api/files/",
    "storage/v1/object/public/",
    "object/public/",
    "storage/v1/object/sign/",
    "object/sign/",
    "storage/v1/object/authenticated/",
    "object/authenticated/",
)
_CANONICAL_COURSE_COVER_PREFIXES = (
    "courses/",
    "media/derived/cover/courses/",
)
_MIME_ALIASES = {
    "image/jpg": "image/jpeg",
}


@dataclass
class CourseCoverBackfillItem:
    course_id: str
    course_owner_id: str | None
    slug: str | None
    title: str | None
    classification: str
    cover_url: str | None
    cover_media_id: str | None
    reason: str
    legacy_storage_bucket: str | None = None
    legacy_storage_path: str | None = None
    legacy_content_type: str | None = None
    legacy_size_bytes: int | None = None
    legacy_object_public: bool | None = None
    asset_state: str | None = None
    asset_storage_bucket: str | None = None
    asset_storage_path: str | None = None
    asset_purpose: str | None = None
    reusable_asset_ids: list[str] = field(default_factory=list)
    planned_action: str | None = None
    planned_media_id: str | None = None
    mutation_action: str | None = None
    assigned_media_id: str | None = None
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class CourseCoverBackfillReport:
    mode: str
    batch_size: int
    courses_scanned: int = 0
    class_counts: dict[str, int] = field(
        default_factory=lambda: {classification: 0 for classification in _ALL_CLASSES}
    )
    migrated_courses: int = 0
    reused_assets: int = 0
    created_assets: int = 0
    skipped_noncanonical: int = 0
    skipped_unverifiable: int = 0
    skipped_hybrid_broken: int = 0
    errors: int = 0
    dry_run_would_migrate_courses: int = 0
    dry_run_would_reuse_assets: int = 0
    dry_run_would_create_assets: int = 0
    would_still_rely_on_legacy_fallback_after_run: int = 0
    items: list[CourseCoverBackfillItem] = field(default_factory=list)

    def add_item(self, item: CourseCoverBackfillItem) -> None:
        self.items.append(item)
        self.courses_scanned += 1
        self.class_counts[item.classification] = (
            self.class_counts.get(item.classification, 0) + 1
        )
        if item.classification == CLASS_LEGACY_MIGRATABLE:
            self.dry_run_would_migrate_courses += 1
            if item.planned_action == "reuse_asset":
                self.dry_run_would_reuse_assets += 1
            elif item.planned_action == "create_asset":
                self.dry_run_would_create_assets += 1
        elif item.classification == CLASS_LEGACY_PUBLIC_BUT_NONCANONICAL:
            self.skipped_noncanonical += 1
        elif item.classification == CLASS_LEGACY_UNVERIFIABLE:
            self.skipped_unverifiable += 1
        elif item.classification == CLASS_HYBRID_BROKEN:
            self.skipped_hybrid_broken += 1

    def finalize(self) -> None:
        skipped_due_apply = sum(
            1
            for item in self.items
            if item.classification == CLASS_LEGACY_MIGRATABLE
            and item.mutation_action not in {"reused_asset", "created_asset"}
        )
        self.would_still_rely_on_legacy_fallback_after_run = (
            self.class_counts.get(CLASS_LEGACY_PUBLIC_BUT_NONCANONICAL, 0)
            + self.class_counts.get(CLASS_LEGACY_UNVERIFIABLE, 0)
            + self.class_counts.get(CLASS_HYBRID_BROKEN, 0)
            + (
                skipped_due_apply
                if self.mode == "apply"
                else 0
            )
        )

    def to_dict(self) -> dict[str, Any]:
        self.finalize()
        return {
            "mode": self.mode,
            "batch_size": self.batch_size,
            "courses_scanned": self.courses_scanned,
            "class_counts": dict(self.class_counts),
            "metrics": {
                "courses_scanned": self.courses_scanned,
                "already_control_plane": self.class_counts.get(
                    CLASS_ALREADY_CONTROL_PLANE, 0
                ),
                "migrated_courses": self.migrated_courses,
                "reused_assets": self.reused_assets,
                "created_assets": self.created_assets,
                "skipped_noncanonical": self.skipped_noncanonical,
                "skipped_unverifiable": self.skipped_unverifiable,
                "skipped_hybrid_broken": self.skipped_hybrid_broken,
                "errors": self.errors,
            },
            "dry_run": {
                "would_migrate_courses": self.dry_run_would_migrate_courses,
                "would_reuse_assets": self.dry_run_would_reuse_assets,
                "would_create_assets": self.dry_run_would_create_assets,
                "would_still_rely_on_legacy_fallback_after_run": self.would_still_rely_on_legacy_fallback_after_run,
            },
            "items": [item.to_dict() for item in self.items],
        }


def _normalize_mime(value: Any) -> str | None:
    raw = str(value or "").strip().lower()
    if not raw:
        return None
    normalized = raw.split(";", 1)[0].strip()
    return _MIME_ALIASES.get(normalized, normalized) or None


def _derive_public_storage_path_candidates(raw_url: str | None) -> tuple[str, ...]:
    raw = str(raw_url or "").strip()
    if not raw:
        return ()

    parsed = urlparse(raw)
    candidate = parsed.path if parsed.scheme in {"http", "https"} or parsed.netloc else raw
    candidate = unquote(candidate).replace("\\", "/").lstrip("/")
    candidate = re.sub(r"/{2,}", "/", candidate)
    for prefix in _URL_PATH_PREFIXES:
        if candidate.startswith(prefix):
            candidate = candidate[len(prefix) :].lstrip("/")
            break

    bucket = settings.media_public_bucket
    bucket_prefix = f"{bucket}/"
    if not candidate.startswith(bucket_prefix):
        return ()

    key = candidate[len(bucket_prefix) :].lstrip("/")
    if not key:
        return ()

    variants: list[str] = []
    current = key
    while current:
        variants.append(current)
        if not current.startswith(bucket_prefix):
            break
        current = current[len(bucket_prefix) :].lstrip("/")

    ordered: list[str] = []
    for variant in reversed(variants):
        if variant not in ordered:
            ordered.append(variant)
    return tuple(ordered)


def _guess_content_type(storage_path: str | None) -> str | None:
    guessed, _ = mimetypes.guess_type(str(storage_path or "").strip())
    return _normalize_mime(guessed)


def _storage_content_type(detail: Mapping[str, Any] | None, storage_path: str | None) -> str | None:
    if detail is None:
        return None
    return _normalize_mime(detail.get("content_type")) or _guess_content_type(storage_path)


def _derive_ingest_format(storage_path: str, content_type: str | None) -> str:
    suffix = Path(storage_path).suffix.lower().lstrip(".")
    if suffix:
        return suffix
    normalized_type = _normalize_mime(content_type) or ""
    if "/" in normalized_type:
        return normalized_type.split("/", 1)[1].split("+", 1)[0]
    return "bin"


def _normalize_asset_candidate(asset: Mapping[str, Any] | None) -> tuple[str | None, str | None]:
    if not asset:
        return None, None
    raw_bucket = str(
        asset.get("streaming_storage_bucket") or asset.get("storage_bucket") or ""
    ).strip()
    raw_path = str(
        asset.get("streaming_object_path") or asset.get("original_object_path") or ""
    ).strip()
    if not raw_bucket or not raw_path:
        return None, None
    try:
        normalized_path = media_paths.normalize_storage_path(raw_bucket, raw_path)
    except Exception:
        return None, None
    return raw_bucket, normalized_path


def _is_canonical_public_course_cover_path(storage_path: str | None) -> bool:
    normalized = str(storage_path or "").strip().lstrip("/")
    if not normalized:
        return False
    if any(normalized.startswith(prefix) for prefix in _CANONICAL_COURSE_COVER_PREFIXES):
        return True
    return False


def _legacy_cover_requires_copy(storage_path: str | None) -> bool:
    normalized = str(storage_path or "").strip().lstrip("/")
    return normalized.startswith("lessons/")


def _build_backfill_course_cover_copy_path(course_id: str, filename: str | None) -> str:
    safe_name = Path(filename or "").name.strip() or "cover.jpg"
    path = (
        Path("media")
        / "derived"
        / "cover"
        / "courses"
        / course_id
        / f"{uuid4().hex}_{safe_name}"
    )
    return media_paths.validate_new_upload_object_path(path.as_posix())


def _select_first_existing_storage_object(
    *,
    bucket: str,
    candidate_paths: Iterable[str],
    storage_details: Mapping[tuple[str, str], dict[str, Any] | None],
) -> tuple[str | None, dict[str, Any] | None]:
    for path in candidate_paths:
        detail = storage_details.get((bucket, path))
        if detail is not None:
            return path, detail
    return None, None


def _valid_control_plane_asset_for_course(
    *,
    course: Mapping[str, Any],
    asset: Mapping[str, Any] | None,
    storage_details: Mapping[tuple[str, str], dict[str, Any] | None],
    storage_table_available: bool,
) -> tuple[bool, str, str | None, str | None]:
    if asset is None:
        return False, "asset_missing", None, None

    asset_course_id = str(asset.get("course_id") or "").strip() or None
    asset_state = str(asset.get("state") or "").strip().lower() or None
    asset_purpose = str(asset.get("purpose") or "").strip().lower() or None
    asset_media_type = str(asset.get("media_type") or "").strip().lower() or None
    course_id = str(course.get("id") or "").strip() or None

    if asset_purpose != "course_cover" or asset_course_id != course_id:
        return False, "invalid_asset_contract", None, None
    if asset_media_type != "image":
        return False, "invalid_asset_media_type", None, None
    if asset_state != "ready":
        return False, "asset_not_ready", None, None

    bucket, path = _normalize_asset_candidate(asset)
    if not bucket or not path:
        return False, "missing_asset_path", None, None
    if bucket != settings.media_public_bucket:
        return False, "asset_not_public_bucket", bucket, path
    if not storage_table_available:
        return False, "storage_verification_unavailable", bucket, path

    detail = storage_details.get((bucket, path))
    if detail is None:
        return False, "asset_object_missing", bucket, path
    if not bool(detail.get("public")):
        return False, "asset_bucket_not_public", bucket, path
    content_type = _storage_content_type(detail, path)
    if not content_type or not content_type.startswith("image/"):
        return False, "asset_object_not_image", bucket, path
    return True, "ready", bucket, path


async def _classify_course(
    *,
    course: Mapping[str, Any],
    asset: Mapping[str, Any] | None,
    storage_details: Mapping[tuple[str, str], dict[str, Any] | None],
    storage_table_available: bool,
) -> CourseCoverBackfillItem:
    course_id = str(course.get("id") or "").strip()
    course_owner_id = str(course.get("created_by") or "").strip() or None
    slug = str(course.get("slug") or "").strip() or None
    title = str(course.get("title") or "").strip() or None
    cover_url = str(course.get("cover_url") or "").strip() or None
    cover_media_id = str(course.get("cover_media_id") or "").strip() or None

    asset_valid, asset_reason, asset_bucket, asset_path = _valid_control_plane_asset_for_course(
        course=course,
        asset=asset,
        storage_details=storage_details,
        storage_table_available=storage_table_available,
    )

    candidate_paths = _derive_public_storage_path_candidates(cover_url)
    legacy_path, legacy_detail = _select_first_existing_storage_object(
        bucket=settings.media_public_bucket,
        candidate_paths=candidate_paths,
        storage_details=storage_details,
    )
    legacy_content_type = _storage_content_type(legacy_detail, legacy_path)
    legacy_size_bytes = (
        int(legacy_detail.get("size_bytes"))
        if legacy_detail is not None and legacy_detail.get("size_bytes") is not None
        else None
    )
    legacy_public = bool(legacy_detail.get("public")) if legacy_detail is not None else None

    if asset_valid:
        if legacy_path is None:
            if cover_media_id and cover_url:
                return CourseCoverBackfillItem(
                    course_id=course_id,
                    course_owner_id=course_owner_id,
                    slug=slug,
                    title=title,
                    classification=CLASS_HYBRID_BROKEN,
                    cover_url=cover_url,
                    cover_media_id=cover_media_id,
                    reason="legacy_cover_url_unverifiable",
                    asset_state=str(asset.get("state") or "").strip().lower() or None,
                    asset_storage_bucket=asset_bucket,
                    asset_storage_path=asset_path,
                    asset_purpose=str(asset.get("purpose") or "").strip().lower() or None,
                )
            return CourseCoverBackfillItem(
                course_id=course_id,
                course_owner_id=course_owner_id,
                slug=slug,
                title=title,
                classification=CLASS_ALREADY_CONTROL_PLANE,
                cover_url=cover_url,
                cover_media_id=cover_media_id,
                reason="control_plane_ready",
                asset_state=str(asset.get("state") or "").strip().lower() or None,
                asset_storage_bucket=asset_bucket,
                asset_storage_path=asset_path,
                asset_purpose=str(asset.get("purpose") or "").strip().lower() or None,
            )
        if asset_bucket == settings.media_public_bucket and asset_path == legacy_path:
            return CourseCoverBackfillItem(
                course_id=course_id,
                course_owner_id=course_owner_id,
                slug=slug,
                title=title,
                classification=CLASS_ALREADY_CONTROL_PLANE,
                cover_url=cover_url,
                cover_media_id=cover_media_id,
                reason="control_plane_ready",
                legacy_storage_bucket=settings.media_public_bucket,
                legacy_storage_path=legacy_path,
                legacy_content_type=legacy_content_type,
                legacy_size_bytes=legacy_size_bytes,
                legacy_object_public=legacy_public,
                asset_state=str(asset.get("state") or "").strip().lower() or None,
                asset_storage_bucket=asset_bucket,
                asset_storage_path=asset_path,
                asset_purpose=str(asset.get("purpose") or "").strip().lower() or None,
            )
        return CourseCoverBackfillItem(
            course_id=course_id,
            course_owner_id=course_owner_id,
            slug=slug,
            title=title,
            classification=CLASS_HYBRID_BROKEN,
            cover_url=cover_url,
            cover_media_id=cover_media_id,
            reason="cover_source_disagrees_with_ready_asset",
            legacy_storage_bucket=settings.media_public_bucket,
            legacy_storage_path=legacy_path,
            legacy_content_type=legacy_content_type,
            legacy_size_bytes=legacy_size_bytes,
            legacy_object_public=legacy_public,
            asset_state=str(asset.get("state") or "").strip().lower() or None,
            asset_storage_bucket=asset_bucket,
            asset_storage_path=asset_path,
            asset_purpose=str(asset.get("purpose") or "").strip().lower() or None,
        )

    if cover_media_id and cover_url:
        return CourseCoverBackfillItem(
            course_id=course_id,
            course_owner_id=course_owner_id,
            slug=slug,
            title=title,
            classification=CLASS_HYBRID_BROKEN,
            cover_url=cover_url,
            cover_media_id=cover_media_id,
            reason=asset_reason,
            legacy_storage_bucket=settings.media_public_bucket if legacy_path else None,
            legacy_storage_path=legacy_path,
            legacy_content_type=legacy_content_type,
            legacy_size_bytes=legacy_size_bytes,
            legacy_object_public=legacy_public,
            asset_state=str(asset.get("state") or "").strip().lower() or None if asset else None,
            asset_storage_bucket=asset_bucket,
            asset_storage_path=asset_path,
            asset_purpose=str(asset.get("purpose") or "").strip().lower() or None if asset else None,
        )

    if not candidate_paths:
        return CourseCoverBackfillItem(
            course_id=course_id,
            course_owner_id=course_owner_id,
            slug=slug,
            title=title,
            classification=CLASS_LEGACY_UNVERIFIABLE,
            cover_url=cover_url,
            cover_media_id=cover_media_id,
            reason="legacy_cover_url_not_in_public_media",
        )

    if not storage_table_available:
        return CourseCoverBackfillItem(
            course_id=course_id,
            course_owner_id=course_owner_id,
            slug=slug,
            title=title,
            classification=CLASS_LEGACY_UNVERIFIABLE,
            cover_url=cover_url,
            cover_media_id=cover_media_id,
            reason="storage_verification_unavailable",
        )

    if legacy_path is None or legacy_detail is None:
        return CourseCoverBackfillItem(
            course_id=course_id,
            course_owner_id=course_owner_id,
            slug=slug,
            title=title,
            classification=CLASS_LEGACY_UNVERIFIABLE,
            cover_url=cover_url,
            cover_media_id=cover_media_id,
            reason="storage_object_missing",
        )

    if not legacy_content_type or not legacy_content_type.startswith("image/"):
        return CourseCoverBackfillItem(
            course_id=course_id,
            course_owner_id=course_owner_id,
            slug=slug,
            title=title,
            classification=CLASS_LEGACY_UNVERIFIABLE,
            cover_url=cover_url,
            cover_media_id=cover_media_id,
            reason="storage_object_not_image",
            legacy_storage_bucket=settings.media_public_bucket,
            legacy_storage_path=legacy_path,
            legacy_content_type=legacy_content_type,
            legacy_size_bytes=legacy_size_bytes,
            legacy_object_public=legacy_public,
        )

    if not legacy_public:
        return CourseCoverBackfillItem(
            course_id=course_id,
            course_owner_id=course_owner_id,
            slug=slug,
            title=title,
            classification=CLASS_LEGACY_PUBLIC_BUT_NONCANONICAL,
            cover_url=cover_url,
            cover_media_id=cover_media_id,
            reason="bucket_not_public",
            legacy_storage_bucket=settings.media_public_bucket,
            legacy_storage_path=legacy_path,
            legacy_content_type=legacy_content_type,
            legacy_size_bytes=legacy_size_bytes,
            legacy_object_public=legacy_public,
        )

    if not _is_canonical_public_course_cover_path(legacy_path):
        if _legacy_cover_requires_copy(legacy_path):
            return CourseCoverBackfillItem(
                course_id=course_id,
                course_owner_id=course_owner_id,
                slug=slug,
                title=title,
                classification=CLASS_LEGACY_MIGRATABLE,
                cover_url=cover_url,
                cover_media_id=cover_media_id,
                reason="legacy_lesson_cover_requires_copy",
                legacy_storage_bucket=settings.media_public_bucket,
                legacy_storage_path=legacy_path,
                legacy_content_type=legacy_content_type,
                legacy_size_bytes=legacy_size_bytes,
                legacy_object_public=legacy_public,
                reusable_asset_ids=[],
                planned_action="create_asset",
                planned_media_id=None,
            )
        return CourseCoverBackfillItem(
            course_id=course_id,
            course_owner_id=course_owner_id,
            slug=slug,
            title=title,
            classification=CLASS_LEGACY_PUBLIC_BUT_NONCANONICAL,
            cover_url=cover_url,
            cover_media_id=cover_media_id,
            reason="noncanonical_public_cover_path",
            legacy_storage_bucket=settings.media_public_bucket,
            legacy_storage_path=legacy_path,
            legacy_content_type=legacy_content_type,
            legacy_size_bytes=legacy_size_bytes,
            legacy_object_public=legacy_public,
        )

    reusable_assets = await media_assets_repo.list_ready_course_cover_assets_for_object(
        course_id=course_id,
        storage_bucket=settings.media_public_bucket,
        storage_path=legacy_path,
    )
    reusable_asset_ids = [
        str(asset_row["id"])
        for asset_row in reusable_assets
        if asset_row.get("id")
    ]
    planned_action = "create_asset"
    planned_media_id = None
    if len(reusable_asset_ids) == 1:
        planned_action = "reuse_asset"
        planned_media_id = reusable_asset_ids[0]
    else:
        exact_assets = [
            asset_row
            for asset_row in reusable_assets
            if str(asset_row.get("storage_bucket") or "").strip() == settings.media_public_bucket
            and str(asset_row.get("original_object_path") or "").strip() == legacy_path
            and str(asset_row.get("streaming_storage_bucket") or "").strip() == settings.media_public_bucket
            and str(asset_row.get("streaming_object_path") or "").strip() == legacy_path
        ]
        if len(exact_assets) == 1 and exact_assets[0].get("id"):
            planned_action = "reuse_asset"
            planned_media_id = str(exact_assets[0]["id"])

    return CourseCoverBackfillItem(
        course_id=course_id,
        course_owner_id=course_owner_id,
        slug=slug,
        title=title,
        classification=CLASS_LEGACY_MIGRATABLE,
        cover_url=cover_url,
        cover_media_id=cover_media_id,
        reason="legacy_public_cover_verified",
        legacy_storage_bucket=settings.media_public_bucket,
        legacy_storage_path=legacy_path,
        legacy_content_type=legacy_content_type,
        legacy_size_bytes=legacy_size_bytes,
        legacy_object_public=legacy_public,
        reusable_asset_ids=reusable_asset_ids,
        planned_action=planned_action,
        planned_media_id=planned_media_id,
    )


async def classify_course_cover_batch(
    rows: Iterable[Mapping[str, Any]],
) -> list[CourseCoverBackfillItem]:
    course_rows = [dict(row) for row in rows]
    if not course_rows:
        return []

    asset_ids = [
        str(row.get("cover_media_id") or "").strip()
        for row in course_rows
        if str(row.get("cover_media_id") or "").strip()
    ]
    assets_by_id = await media_assets_repo.get_media_assets(asset_ids)

    pairs: set[tuple[str, str]] = set()
    for row in course_rows:
        cover_url = str(row.get("cover_url") or "").strip() or None
        for candidate_path in _derive_public_storage_path_candidates(cover_url):
            pairs.add((settings.media_public_bucket, candidate_path))
        cover_media_id = str(row.get("cover_media_id") or "").strip() or None
        asset = assets_by_id.get(cover_media_id) if cover_media_id else None
        asset_bucket, asset_path = _normalize_asset_candidate(asset)
        if asset_bucket and asset_path:
            pairs.add((asset_bucket, asset_path))

    storage_details, storage_table_available = await storage_objects.fetch_storage_object_details(
        pairs
    )

    items: list[CourseCoverBackfillItem] = []
    for row in course_rows:
        cover_media_id = str(row.get("cover_media_id") or "").strip() or None
        item = await _classify_course(
            course=row,
            asset=assets_by_id.get(cover_media_id) if cover_media_id else None,
            storage_details=storage_details,
            storage_table_available=storage_table_available,
        )
        items.append(item)
    return items


async def _apply_item(report: CourseCoverBackfillReport, item: CourseCoverBackfillItem) -> None:
    if item.classification != CLASS_LEGACY_MIGRATABLE:
        return

    try:
        assigned_media_id = item.planned_media_id
        mutation_action = None

        if item.planned_action == "reuse_asset" and assigned_media_id:
            updated = await courses_repo.set_course_cover_media_id_if_unset(
                course_id=item.course_id,
                cover_media_id=assigned_media_id,
            )
            if updated:
                report.migrated_courses += 1
                report.reused_assets += 1
                mutation_action = "reused_asset"
            else:
                mutation_action = "skipped_course_already_has_cover_media_id"
        else:
            requires_copy = _legacy_cover_requires_copy(item.legacy_storage_path)
            if requires_copy:
                reusable_assets: list[dict[str, Any]] = []
                exact_assets: list[dict[str, Any]] = []
            else:
                reusable_assets = await media_assets_repo.list_ready_course_cover_assets_for_object(
                    course_id=item.course_id,
                    storage_bucket=item.legacy_storage_bucket or settings.media_public_bucket,
                    storage_path=item.legacy_storage_path or "",
                )
                exact_assets = [
                    asset_row
                    for asset_row in reusable_assets
                    if str(asset_row.get("storage_bucket") or "").strip() == settings.media_public_bucket
                    and str(asset_row.get("original_object_path") or "").strip() == item.legacy_storage_path
                    and str(asset_row.get("streaming_storage_bucket") or "").strip() == settings.media_public_bucket
                    and str(asset_row.get("streaming_object_path") or "").strip() == item.legacy_storage_path
                    and asset_row.get("id")
                ]
            if len(exact_assets) == 1:
                assigned_media_id = str(exact_assets[0]["id"])
                updated = await courses_repo.set_course_cover_media_id_if_unset(
                    course_id=item.course_id,
                    cover_media_id=assigned_media_id,
                )
                if updated:
                    report.migrated_courses += 1
                    report.reused_assets += 1
                    mutation_action = "reused_asset"
                else:
                    mutation_action = "skipped_course_already_has_cover_media_id"
            else:
                ingest_format = _derive_ingest_format(
                    item.legacy_storage_path or "",
                    item.legacy_content_type,
                )
                storage_bucket = item.legacy_storage_bucket or settings.media_public_bucket
                storage_path = item.legacy_storage_path or ""
                if requires_copy:
                    storage_bucket = settings.media_public_bucket
                    storage_path = _build_backfill_course_cover_copy_path(
                        item.course_id,
                        Path(item.legacy_storage_path or "").name or None,
                    )
                    await storage_service.copy_object(
                        source_bucket=item.legacy_storage_bucket or settings.media_public_bucket,
                        source_path=item.legacy_storage_path or "",
                        destination_bucket=storage_bucket,
                        destination_path=storage_path,
                        content_type=item.legacy_content_type,
                        cache_seconds=settings.media_public_cache_seconds,
                    )
                    logger.info(
                        "COURSE_COVER_BACKFILL_STORAGE_COPIED course_id=%s source_bucket=%s source_path=%s destination_bucket=%s destination_path=%s",
                        item.course_id,
                        item.legacy_storage_bucket or settings.media_public_bucket,
                        item.legacy_storage_path or "<missing>",
                        storage_bucket,
                        storage_path,
                    )
                created = await media_assets_repo.create_ready_public_course_cover_asset(
                    owner_id=item.course_owner_id,
                    course_id=item.course_id,
                    storage_bucket=storage_bucket,
                    storage_path=storage_path,
                    content_type=item.legacy_content_type,
                    filename=Path(item.legacy_storage_path or "").name or None,
                    size_bytes=item.legacy_size_bytes,
                    ingest_format=ingest_format,
                    codec=None,
                )
                if not created or not created.get("id"):
                    raise RuntimeError("create_ready_public_course_cover_asset_failed")
                assigned_media_id = str(created["id"])
                updated = await courses_repo.set_course_cover_media_id_if_unset(
                    course_id=item.course_id,
                    cover_media_id=assigned_media_id,
                )
                if updated:
                    report.migrated_courses += 1
                    report.created_assets += 1
                    mutation_action = "created_asset"
                else:
                    mutation_action = "created_asset_unassigned_course_already_has_cover_media_id"

        item.assigned_media_id = assigned_media_id
        item.mutation_action = mutation_action
        logger.info(
            "COURSE_COVER_BACKFILL_APPLY course_id=%s slug=%s classification=%s action=%s assigned_media_id=%s",
            item.course_id,
            item.slug or "<missing>",
            item.classification,
            item.mutation_action or "<none>",
            item.assigned_media_id or "<missing>",
        )
    except Exception as exc:
        report.errors += 1
        item.error = str(exc)
        item.mutation_action = "error"
        logger.exception(
            "COURSE_COVER_BACKFILL_ERROR course_id=%s slug=%s classification=%s",
            item.course_id,
            item.slug or "<missing>",
            item.classification,
        )


async def run_course_cover_backfill(
    *,
    apply: bool = False,
    batch_size: int = 100,
    max_courses: int | None = None,
) -> CourseCoverBackfillReport:
    normalized_batch_size = max(1, int(batch_size))
    report = CourseCoverBackfillReport(
        mode="apply" if apply else "dry_run",
        batch_size=normalized_batch_size,
    )

    after_id: str | None = None
    remaining = None if max_courses is None else max(0, int(max_courses))

    while remaining is None or remaining > 0:
        limit = normalized_batch_size if remaining is None else min(normalized_batch_size, remaining)
        rows = await courses_repo.list_courses_with_cover_url(limit=limit, after_id=after_id)
        if not rows:
            break

        items = await classify_course_cover_batch(rows)
        for item in items:
            report.add_item(item)
            logger.info(
                "COURSE_COVER_BACKFILL_PREFLIGHT course_id=%s slug=%s classification=%s reason=%s planned_action=%s cover_media_id=%s legacy_path=%s",
                item.course_id,
                item.slug or "<missing>",
                item.classification,
                item.reason,
                item.planned_action or "<none>",
                item.cover_media_id or "<missing>",
                item.legacy_storage_path or "<missing>",
            )
            if apply:
                await _apply_item(report, item)

        after_id = str(rows[-1]["id"])
        if remaining is not None:
            remaining -= len(rows)

    report.finalize()
    logger.info(
        "COURSE_COVER_BACKFILL_SUMMARY mode=%s courses_scanned=%s already_control_plane=%s migrated_courses=%s reused_assets=%s created_assets=%s skipped_noncanonical=%s skipped_unverifiable=%s skipped_hybrid_broken=%s errors=%s fallback_after_run=%s",
        report.mode,
        report.courses_scanned,
        report.class_counts.get(CLASS_ALREADY_CONTROL_PLANE, 0),
        report.migrated_courses,
        report.reused_assets,
        report.created_assets,
        report.skipped_noncanonical,
        report.skipped_unverifiable,
        report.skipped_hybrid_broken,
        report.errors,
        report.would_still_rely_on_legacy_fallback_after_run,
    )
    return report
