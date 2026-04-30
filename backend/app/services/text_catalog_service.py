from __future__ import annotations

import hashlib
import json
from typing import Final

CATALOG_VERSION: Final[str] = "catalog_v1"
COURSE_CTA_BUNDLE_ID: Final[str] = "course_cta.v1"
DEFAULT_LOCALE: Final[str] = "sv-SE"


class TextCatalogError(RuntimeError):
    pass


_COURSE_CTA_TEXT_IDS: Final[tuple[str, ...]] = (
    "course.cta.continue",
    "course.cta.enroll",
    "course.cta.buy",
    "course.cta.unavailable",
    "lesson.cta.continue",
    "lesson.cta.start",
    "lesson.cta.buy",
    "lesson.cta.unavailable",
)

_TEXTS_BY_BUNDLE: Final[dict[str, dict[str, str]]] = {
    COURSE_CTA_BUNDLE_ID: {
        "course.cta.continue": "Fortsätt",
        "course.cta.enroll": "Börja kursen",
        "course.cta.buy": "Köp kursen",
        "course.cta.unavailable": "Inte tillgänglig",
        "lesson.cta.continue": "Fortsätt",
        "lesson.cta.start": "Börja kursen",
        "lesson.cta.buy": "Köp kursen",
        "lesson.cta.unavailable": "Inte tillgänglig",
    }
}

_REQUIRED_TEXT_IDS_BY_BUNDLE: Final[dict[str, tuple[str, ...]]] = {
    COURSE_CTA_BUNDLE_ID: _COURSE_CTA_TEXT_IDS,
}


def get_bundle(bundle_id: str, locale: str) -> dict[str, object]:
    if locale != DEFAULT_LOCALE:
        raise TextCatalogError(f"Unsupported text catalog locale: {locale}")

    try:
        source_texts = _TEXTS_BY_BUNDLE[bundle_id]
        required_text_ids = _REQUIRED_TEXT_IDS_BY_BUNDLE[bundle_id]
    except KeyError as exc:
        raise TextCatalogError(f"Unknown text catalog bundle: {bundle_id}") from exc

    texts: dict[str, str] = {}
    for text_id in required_text_ids:
        value = source_texts.get(text_id)
        if not value:
            raise TextCatalogError(
                f"Missing text catalog value: {bundle_id}:{text_id}"
            )
        texts[text_id] = value

    bundle: dict[str, object] = {
        "bundle_id": bundle_id,
        "locale": locale,
        "version": CATALOG_VERSION,
        "texts": texts,
    }
    bundle["hash"] = _stable_hash(bundle)
    return bundle


def _stable_hash(bundle: dict[str, object]) -> str:
    encoded = json.dumps(
        bundle,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return f"sha256:{hashlib.sha256(encoded).hexdigest()}"
