#!/usr/bin/env python3
"""
Import a course (text + media) into the local backend via /studio endpoints.

Manifest format (YAML or JSON):

title: Foundations of SoulWisdom
slug: foundations-of-soulwisdom
description: Intro to practices and core ideas
is_free_intro: true
is_published: false
price_cents: 0
cover_url: null  # optional legacy field; importer does not write this directly
lessons:
  - title: Välkommen
    markdown: lessons/welcome.md   # path to a .md file (UTF-8)
    is_intro: true                 # optional, defaults to false
    media:
      - path: media/welcome.jpg
      - path: media/intro_audio.mp3
  - title: Rensa energifältet
    markdown: lessons/cleanse.md
    media:
      - path: media/cleanse_audio.mp3

Usage:
  python scripts/import_course.py \
    --base-url http://127.0.0.1:8080 \
    --email teacher@example.com \
    --password teacher123 \
    --manifest /path/to/course.yaml

Notes:
- Live writes are disabled until this importer is rebuilt for the canonical
  lesson structure/content and media upload-completion-placement flow.
- The script requires PyYAML for YAML manifests; JSON works without extra deps.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
from pathlib import Path
from typing import Any, Dict, List

import requests

try:
    import yaml  # type: ignore
except Exception:  # pragma: no cover - optional dependency
    yaml = None  # type: ignore


DISABLED_REASON = (
    "import_course.py is disabled: it still contains legacy write helpers for "
    "removed /studio/lessons and /api/media routes. Rebuild it against the "
    "canonical lesson structure/content and media placement pipeline before use."
)


def load_manifest(path: Path) -> Dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() in {".yaml", ".yml"}:
        if yaml is None:
            raise SystemExit("PyYAML not installed. Either install pyyaml or use JSON manifest.")
        return yaml.safe_load(text)
    return json.loads(text)


def login(base_url: str, email: str, password: str) -> str:
    r = requests.post(
        f"{base_url}/auth/login",
        json={"email": email, "password": password},
        timeout=30,
    )
    r.raise_for_status()
    data = r.json()
    token = data.get("access_token")
    if not token:
        raise RuntimeError("login failed: missing access_token")
    return token


def post_json(base_url: str, path: str, token: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    r = requests.post(
        f"{base_url}{path}",
        headers={"Authorization": f"Bearer {token}"},
        json=payload,
        timeout=60,
    )
    if r.status_code >= 400:
        raise RuntimeError(f"POST {path} failed: {r.status_code} {r.text}")
    return r.json()


def get_json(base_url: str, path: str, token: str | None = None) -> Dict[str, Any]:
    headers = {"Authorization": f"Bearer {token}"} if token else None
    r = requests.get(f"{base_url}{path}", headers=headers, timeout=60)
    if r.status_code >= 400:
        raise RuntimeError(f"GET {path} failed: {r.status_code} {r.text}")
    return r.json()


def delete_media(base_url: str, token: str, media_id: str) -> None:
    r = requests.delete(
        f"{base_url}/studio/media/{media_id}",
        headers={"Authorization": f"Bearer {token}"},
        timeout=60,
    )
    if r.status_code >= 400:
        raise RuntimeError(f"DELETE /studio/media/{media_id} failed: {r.status_code} {r.text}")


def list_lesson_media(base_url: str, token: str, lesson_id: str) -> List[Dict[str, Any]]:
    r = requests.get(
        f"{base_url}/studio/lessons/{lesson_id}/media",
        headers={"Authorization": f"Bearer {token}"},
        timeout=60,
    )
    if r.status_code >= 400:
        raise RuntimeError(f"GET /studio/lessons/{lesson_id}/media failed: {r.status_code} {r.text}")
    data = r.json()
    items = data.get("items") if isinstance(data, dict) else None
    return items if isinstance(items, list) else []


def _lesson_media_id(item: Dict[str, Any]) -> str | None:
    value = str(item.get("lesson_media_id") or item.get("id") or "").strip()
    return value or None


def _lesson_media_kind(item: Dict[str, Any]) -> str | None:
    value = str(item.get("media_type") or item.get("kind") or "").strip()
    return value or None


def _lesson_media_resolved_url(item: Dict[str, Any]) -> str | None:
    media = item.get("media")
    if not isinstance(media, dict):
        return None
    value = str(media.get("resolved_url") or "").strip()
    return value or None


def get_lesson_media_item(
    base_url: str,
    token: str,
    lesson_id: str,
    lesson_media_id: str,
) -> Dict[str, Any]:
    for item in list_lesson_media(base_url, token, lesson_id):
        if _lesson_media_id(item) == lesson_media_id:
            return item
    raise RuntimeError(
        f"GET /studio/lessons/{lesson_id}/media missing lesson_media_id={lesson_media_id}"
    )


def list_course_lessons(base_url: str, token: str, course_id: str) -> List[Dict[str, Any]]:
    data = get_json(base_url, f"/studio/courses/{course_id}/lessons", token)
    items = data.get("items") if isinstance(data, dict) else None
    return items if isinstance(items, list) else []


def create_course(base_url: str, token: str, manifest: Dict[str, Any]) -> Dict[str, Any]:
    fields = {
        "title": manifest["title"],
        "slug": manifest["slug"],
        "description": manifest.get("description"),
        "video_url": manifest.get("video_url"),
        "is_free_intro": bool(manifest.get("is_free_intro", False)),
        "is_published": bool(manifest.get("is_published", False)),
        "price_cents": manifest.get("price_cents"),
        "branch": manifest.get("branch"),
    }
    # If a course with the same slug exists, return it instead of failing.
    slug = fields.get("slug")
    if slug:
        try:
            existing = get_json(base_url, f"/courses/by-slug/{slug}")
            if existing and existing.get("course"):
                return existing["course"]
        except Exception:
            # Ignore lookup errors and attempt creation
            pass

    try:
        return post_json(base_url, "/studio/courses", token, fields)
    except RuntimeError as e:
        # Fallback: if creation failed (e.g., unique violation), try fetching by slug
        if slug:
            try:
                existing = get_json(base_url, f"/courses/by-slug/{slug}")
                if existing and existing.get("course"):
                    return existing["course"]
            except Exception:
                pass
        raise e


def patch_lesson(base_url: str, token: str, lesson_id: str, fields: Dict[str, Any]) -> Dict[str, Any]:
    r = requests.patch(
        f"{base_url}/studio/lessons/{lesson_id}",
        headers={"Authorization": f"Bearer {token}"},
        json=fields,
        timeout=60,
    )
    if r.status_code >= 400:
        raise RuntimeError(f"PATCH /studio/lessons/{lesson_id} failed: {r.status_code} {r.text}")
    return r.json()


def create_lesson(
    base_url: str,
    token: str,
    course_id: str,
    title: str,
    markdown: str | None,
    position: int,
    is_intro: bool,
) -> Dict[str, Any]:
    payload = {
        "course_id": course_id,
        "title": title,
        "content_markdown": markdown,
        "position": position,
        "is_intro": is_intro,
    }
    return post_json(base_url, "/studio/lessons", token, payload)


def upload_media(base_url: str, token: str, lesson_id: str, file_path: Path, is_intro: bool = False) -> Dict[str, Any]:
    mime, _ = mimetypes.guess_type(str(file_path))
    with file_path.open("rb") as fh:
        files = {
            "file": (file_path.name, fh, mime or "application/octet-stream"),
        }
        data = {"is_intro": str(bool(is_intro)).lower()}
        r = requests.post(
            f"{base_url}/studio/lessons/{lesson_id}/media",
            headers={"Authorization": f"Bearer {token}"},
            files=files,
            data=data,
            timeout=600,
        )
    if r.status_code >= 400:
        raise RuntimeError(f"Upload failed for {file_path}: {r.status_code} {r.text}")
    payload = r.json()
    lesson_media_id = _lesson_media_id(payload)
    if lesson_media_id is None:
        raise RuntimeError(f"Upload failed for {file_path}: missing lesson media id")
    return get_lesson_media_item(base_url, token, lesson_id, lesson_media_id)


def _validate_file(path: Path, errors: List[str], warnings: List[str], max_size_mb: int | None) -> None:
    if not path.exists():
        errors.append(f"Missing file: {path}")
        return
    if not path.is_file():
        errors.append(f"Not a regular file: {path}")
        return
    if max_size_mb is not None:
        size = path.stat().st_size
        if size > max_size_mb * 1024 * 1024:
            warnings.append(
                f"Large file ({size/1024/1024:.1f} MB) exceeds --max-size-mb={max_size_mb}: {path}"
            )


def validate_manifest(
    manifest: Dict[str, Any],
    base_dir: Path,
    *,
    max_size_mb: int | None = None,
) -> tuple[list[str], list[str], dict[str, int]]:
    errors: list[str] = []
    warnings: list[str] = []
    stats = {"lessons": 0, "media": 0}

    # Required fields
    if not str(manifest.get("title") or "").strip():
        errors.append("Missing required field: title")
    if not str(manifest.get("slug") or "").strip():
        errors.append("Missing required field: slug")

    # Cover
    cover_raw = manifest.get("cover_path") or manifest.get("coverFile")
    if cover_raw:
        _validate_file((base_dir / str(cover_raw)).resolve(), errors, warnings, max_size_mb)
    if str(manifest.get("cover_url") or "").strip():
        warnings.append(
            "Field 'cover_url' is legacy compatibility data and is ignored by the importer."
        )

    lessons = manifest.get("lessons") or []
    if not isinstance(lessons, list):
        errors.append("Field 'lessons' must be a list if present")
        lessons = []

    for li, lesson in enumerate(lessons, start=1):
        stats["lessons"] += 1
        if not isinstance(lesson, dict):
            errors.append(f"lessons[{li}] must be an object")
            continue
        lt = (lesson.get("title") or "").strip()
        if not lt:
            warnings.append(f"lessons[{li}] has empty title")

        md_rel = lesson.get("markdown")
        if md_rel:
            _validate_file((base_dir / str(md_rel)).resolve(), errors, warnings, max_size_mb)

        media_list = lesson.get("media") or []
        if not isinstance(media_list, list):
            errors.append(f"lessons[{li}].media must be a list if present")
            continue
        for mi_idx, media in enumerate(media_list, start=1):
            stats["media"] += 1
            rel = media.get("path") if isinstance(media, dict) else media
            if not isinstance(rel, str):
                errors.append(
                    f"lessons[{li}].media[{mi_idx}] must be a string path or object with 'path'"
                )
                continue
            _validate_file((base_dir / rel).resolve(), errors, warnings, max_size_mb)

    return errors, warnings, stats


def main() -> None:
    raise SystemExit(DISABLED_REASON)

    ap = argparse.ArgumentParser(description="Import course into backend via /studio endpoints")
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--email", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument(
        "--create-assets-lesson",
        action="store_true",
        help=(
            "Create a dedicated '_Course Assets' lesson to store the cover image.\n"
            "If not set, the cover is uploaded to the first created lesson."
        ),
    )
    ap.add_argument(
        "--cleanup-duplicates",
        action="store_true",
        help="Delete duplicate media entries (same original_name) after import.",
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate manifest and referenced files without contacting the server.",
    )
    ap.add_argument(
        "--max-size-mb",
        type=int,
        default=None,
        help="Warn if any referenced file exceeds this size (MB).",
    )
    args = ap.parse_args()

    base = args.base_url.rstrip("/")
    manifest_path = Path(args.manifest)
    manifest_dir = manifest_path.parent.resolve()
    manifest = load_manifest(manifest_path)
    manifest_cover_url = str(manifest.get("cover_url") or "").strip() or None

    # Dry run: validate and exit
    errors, warnings, stats = validate_manifest(
        manifest, manifest_dir, max_size_mb=args.max_size_mb
    )
    if args.dry_run:
        print("=== Course manifest validation ===")
        print(f"Lessons: {stats['lessons']}  Media: {stats['media']}")
        if warnings:
            print("\nWarnings:")
            for w in warnings:
                print(f"  - {w}")
        if errors:
            print("\nErrors:")
            for e in errors:
                print(f"  - {e}")
            raise SystemExit(1)
        print("\nValidation OK. Use without --dry-run to import.")
        return

    # Real import flow
    token = login(base, args.email, args.password)
    course = create_course(base, token, manifest)
    course_id = course.get("id")
    if not course_id:
        raise RuntimeError("create_course: missing id")
    print(f"Created course: {course_id} {course.get('title')}")
    if manifest_cover_url:
        print(
            "  ! manifest cover_url is ignored for active cover writes;"
            " assign course covers in Studio after import"
        )

    cover_path_raw = manifest.get("cover_path") or manifest.get("coverFile")
    cover_path: Path | None = None
    if cover_path_raw:
        p = (manifest_dir / str(cover_path_raw)).resolve()
        if not p.exists():
            raise FileNotFoundError(f"Cover file not found: {p}")
        cover_path = p
    if cover_path is not None:
        print(
            "  ! manifest cover_path is ignored for course-cover assignment;"
            " assign course covers in Studio after import"
        )

    existing_lessons_by_position: Dict[int, Dict[str, Any]] = {}
    existing_lessons_by_title: Dict[str, List[Dict[str, Any]]] = {}
    try:
        for item in list_course_lessons(base, token, course_id):
            if isinstance(item, dict) and item.get("title"):
                position = item.get("position")
                if isinstance(position, int):
                    existing_lessons_by_position[position] = item
                existing_lessons_by_title.setdefault(item["title"], []).append(item)
    except Exception as prefetch_error:
        print(f"  ! could not prefetch existing lessons: {prefetch_error}")

    lessons: List[Dict[str, Any]] = manifest.get("lessons", [])
    for li, lesson in enumerate(lessons, start=1):
        md_content = None
        md_path = lesson.get("markdown")
        if md_path:
            md_full = (manifest_dir / md_path).resolve()
            md_content = md_full.read_text(encoding="utf-8")
        is_intro = bool(lesson.get("is_intro", False))
        lesson_title = lesson.get("title")
        lesson_id = None
        payload = {
            "title": lesson_title,
            "content_markdown": md_content,
            "position": li,
            "is_intro": is_intro,
        }
        existing_lesson = existing_lessons_by_position.get(li)
        if existing_lesson and existing_lesson.get("title") != lesson_title:
            title_matches = existing_lessons_by_title.get(lesson_title) or []
            existing_lesson = title_matches[0] if len(title_matches) == 1 else None
        if existing_lesson:
            lesson_id = existing_lesson.get("id")
            try:
                patch_lesson(base, token, lesson_id, payload)
                print(f"  Lesson {li} (updated): {lesson_title} ({lesson_id}) intro={is_intro}")
            except Exception as patch_error:
                print(f"  ! update lesson '{lesson_title}' failed: {patch_error}")
        else:
            try:
                new_lesson = create_lesson(
                    base, token, course_id, lesson_title, md_content, li, is_intro
                )
                lesson_id = new_lesson.get("id")
                if not lesson_id:
                    raise RuntimeError("create_lesson: missing id")
                print(f"  Lesson {li}: {new_lesson.get('title')} ({lesson_id}) intro={is_intro}")
            except RuntimeError as lesson_error:
                print(f"  ! create_lesson failed for '{lesson_title}': {lesson_error}")
                try:
                    for item in list_course_lessons(base, token, course_id):
                        if (
                            isinstance(item, dict)
                            and item.get("title") == lesson_title
                            and item.get("id")
                        ):
                            lesson_id = item["id"]
                            position = item.get("position")
                            if isinstance(position, int):
                                existing_lessons_by_position[position] = item
                            existing_lessons_by_title.setdefault(
                                lesson_title, []
                            ).append(item)
                            print(f"    -> reused existing lesson '{lesson_title}' ({lesson_id})")
                            break
                except Exception as refresh_error:
                    print(f"    ! refresh lessons failed: {refresh_error}")
                if not lesson_id:
                    print(f"    !! skipping lesson '{lesson_title}'")
                    continue
        if lesson_id:
            cache_entry = {
                "id": lesson_id,
                "title": lesson_title,
                "position": li,
            }
            existing_lessons_by_position[li] = cache_entry
            title_bucket = existing_lessons_by_title.setdefault(lesson_title, [])
            if not any(item.get("id") == lesson_id for item in title_bucket):
                title_bucket.append(cache_entry)

        if not lesson_id:
            continue

        try:
            existing_media = list_lesson_media(base, token, lesson_id)
        except Exception as media_error:
            print(f"    ! fetch media for lesson '{lesson_title}' failed: {media_error}")
            existing_media = []

        media_by_name: Dict[str, List[Dict[str, Any]]] = {}
        for item in existing_media:
            original_name = item.get("original_name")
            if not original_name:
                storage_path = item.get("storage_path") or ""
                original_name = Path(storage_path).name if storage_path else None
            if original_name:
                media_by_name.setdefault(original_name, []).append(item)

        manifest_media = lesson.get("media", []) or []
        for media in manifest_media:
            rel = media.get("path") if isinstance(media, dict) else media
            if not isinstance(rel, str):
                continue
            media_path = (manifest_dir / rel).resolve()
            if not media_path.exists():
                raise FileNotFoundError(f"Media file not found: {media_path}")
            filename = media_path.name
            existing_list = media_by_name.get(filename)
            if existing_list is not None:
                existing_list = list(existing_list)
            else:
                existing_list = []
            if existing_list:
                reused_item = existing_list.pop(0)
                print(
                    f"    ~ reuse media: {filename} ->"
                    f" {_lesson_media_id(reused_item)}"
                )
                if args.cleanup_duplicates:
                    for duplicate in list(existing_list):
                        media_id = _lesson_media_id(duplicate)
                        if media_id:
                            try:
                                delete_media(base, token, media_id)
                                print(f"      - deleted duplicate media {media_id}")
                            except Exception as delete_error:
                                print(f"      ! delete duplicate failed: {delete_error}")
                    media_by_name[filename] = []
                else:
                    media_by_name[filename] = existing_list
                continue

            item = upload_media(base, token, lesson_id, media_path, is_intro=False)
            resolved_url = _lesson_media_resolved_url(item)
            print(
                "    + media:"
                f" {media_path.name} -> {_lesson_media_id(item)}"
                f" {_lesson_media_kind(item)}"
                f"{f' {resolved_url}' if resolved_url else ''}"
            )
            media_by_name.setdefault(filename, []).append(item)

    print("Import completed.")


if __name__ == "__main__":
    main()
