from __future__ import annotations

import hashlib
import json
from typing import Any, Final, Mapping

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

_COURSE_CTA_TEXT_ID_BY_TYPE: Final[dict[str, str]] = {
    "continue": "course.cta.continue",
    "enroll": "course.cta.enroll",
    "buy": "course.cta.buy",
    "blocked": "course.cta.unavailable",
    "unavailable": "course.cta.unavailable",
}

_LESSON_CTA_TEXT_ID_BY_TYPE: Final[dict[str, str]] = {
    "continue": "lesson.cta.continue",
    "enroll": "lesson.cta.start",
    "buy": "lesson.cta.buy",
    "blocked": "lesson.cta.unavailable",
    "unavailable": "lesson.cta.unavailable",
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


def attach_text_bundles(
    response: Any,
    required_bundle_ids: list[str],
    locale: str,
) -> dict[str, Any]:
    payload = _response_payload(response)
    if "text_bundle" in payload:
        raise TextCatalogError("Singular text_bundle is not a valid response field")

    bundles = _required_bundles(required_bundle_ids, locale)
    payload["text_bundles"] = bundles
    _validate_cta_text_bundle_contract(payload, bundles)
    return payload


def _response_payload(response: Any) -> dict[str, Any]:
    if hasattr(response, "model_dump"):
        return response.model_dump(mode="json")
    if isinstance(response, Mapping):
        return dict(response)
    raise TextCatalogError("Text bundle response cannot be serialized")


def _required_bundles(bundle_ids: list[str], locale: str) -> list[dict[str, object]]:
    seen: set[tuple[str, str]] = set()
    bundles: list[dict[str, object]] = []
    for bundle_id in bundle_ids:
        bundle = get_bundle(bundle_id, locale)
        key = _bundle_key(bundle)
        if key in seen:
            raise TextCatalogError(
                f"Duplicate text bundle requested: {bundle_id}:{locale}"
            )
        seen.add(key)
        bundles.append(bundle)
    return bundles


def _bundle_key(bundle: Mapping[str, object]) -> tuple[str, str]:
    bundle_id = bundle.get("bundle_id")
    locale = bundle.get("locale")
    if not isinstance(bundle_id, str) or not isinstance(locale, str):
        raise TextCatalogError("Text bundle identity is incomplete")
    return bundle_id, locale


def _validate_cta_text_bundle_contract(
    payload: dict[str, Any],
    bundles: list[Mapping[str, object]],
) -> None:
    cta = payload.get("cta")
    if cta is None:
        return
    if not isinstance(cta, dict):
        raise TextCatalogError("CTA payload must be an object")

    cta.pop("label", None)
    text_id = cta.get("text_id")
    if text_id is None:
        text_id = _cta_text_id_for_payload(payload, cta)
        cta["text_id"] = text_id
    if not isinstance(text_id, str) or not text_id:
        raise TextCatalogError("CTA text_id is missing")

    if not _bundle_contains_text_id(bundles, text_id):
        raise TextCatalogError(f"CTA text_id has no text bundle value: {text_id}")


def _cta_text_id_for_payload(payload: Mapping[str, Any], cta: Mapping[str, Any]) -> str:
    cta_type = cta.get("type")
    if not isinstance(cta_type, str):
        raise TextCatalogError("CTA type is missing")

    if "course" in payload:
        text_ids = _COURSE_CTA_TEXT_ID_BY_TYPE
    elif "lesson" in payload:
        text_ids = _LESSON_CTA_TEXT_ID_BY_TYPE
    else:
        raise TextCatalogError("CTA surface is missing")

    try:
        return text_ids[cta_type]
    except KeyError as exc:
        raise TextCatalogError(f"Unknown CTA type: {cta_type}") from exc


def _bundle_contains_text_id(
    bundles: list[Mapping[str, object]],
    text_id: str,
) -> bool:
    for bundle in bundles:
        texts = bundle.get("texts")
        if isinstance(texts, Mapping) and text_id in texts:
            return True
    return False


def _stable_hash(bundle: dict[str, object]) -> str:
    encoded = json.dumps(
        bundle,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return f"sha256:{hashlib.sha256(encoded).hexdigest()}"
