from __future__ import annotations

from typing import Final

SPECIAL_OFFER_OVERWRITE_CONFIRMATION: Final[str] = (
    "studio_editor.special_offer.overwrite_confirmation"
)
SPECIAL_OFFER_GENERATE_SUCCESS: Final[str] = (
    "studio_editor.special_offer.generate_success"
)
SPECIAL_OFFER_GENERATE_FAILED: Final[str] = (
    "studio_editor.special_offer.generate_failed"
)
SPECIAL_OFFER_REGENERATE_SUCCESS: Final[str] = (
    "studio_editor.special_offer.regenerate_success"
)
SPECIAL_OFFER_REGENERATE_FAILED: Final[str] = (
    "studio_editor.special_offer.regenerate_failed"
)
SPECIAL_OFFER_CONFLICT_EXISTS: Final[str] = (
    "studio_editor.special_offer.conflict_exists"
)
SPECIAL_OFFER_NO_OUTPUT_TO_REGENERATE: Final[str] = (
    "studio_editor.special_offer.no_output_to_regenerate"
)
SPECIAL_OFFER_INVALID_INPUT: Final[str] = (
    "studio_editor.special_offer.invalid_input"
)

_TEXT_BY_ID: Final[dict[str, str]] = {
    SPECIAL_OFFER_OVERWRITE_CONFIRMATION: (
        "Detta kommer att ersätta den befintliga erbjudandebilden. Vill du fortsätta?"
    ),
    SPECIAL_OFFER_GENERATE_SUCCESS: "Erbjudandebilden har skapats.",
    SPECIAL_OFFER_GENERATE_FAILED: "Erbjudandebilden kunde inte skapas.",
    SPECIAL_OFFER_REGENERATE_SUCCESS: "Erbjudandebilden har uppdaterats.",
    SPECIAL_OFFER_REGENERATE_FAILED: "Erbjudandebilden kunde inte uppdateras.",
    SPECIAL_OFFER_CONFLICT_EXISTS: (
        "Det finns redan en erbjudandebild för det här erbjudandet."
    ),
    SPECIAL_OFFER_NO_OUTPUT_TO_REGENERATE: (
        "Det finns ingen befintlig erbjudandebild att ersätta."
    ),
    SPECIAL_OFFER_INVALID_INPUT: "Kontrollera uppgifterna och försök igen.",
}


def get_special_offer_text(text_id: str) -> str:
    try:
        return _TEXT_BY_ID[text_id]
    except KeyError as exc:
        raise KeyError(f"Unknown special-offer text id: {text_id}") from exc


def get_special_offer_status_text_id(
    *,
    status: str | None,
    overwrite_applied: bool,
    has_active_output: bool,
) -> str | None:
    if status is None:
        return None

    normalized_status = str(status).strip()
    if normalized_status == "succeeded":
        if overwrite_applied:
            return SPECIAL_OFFER_REGENERATE_SUCCESS
        return SPECIAL_OFFER_GENERATE_SUCCESS
    if normalized_status == "failed":
        if has_active_output:
            return SPECIAL_OFFER_REGENERATE_FAILED
        return SPECIAL_OFFER_GENERATE_FAILED
    return None


def get_special_offer_error_text_id(
    error_code: str,
    *,
    is_regenerate: bool,
) -> str | None:
    normalized_error_code = str(error_code or "").strip()
    if normalized_error_code in {
        "special_offer_asset_already_exists",
        "special_offer_output_conflict",
    }:
        return SPECIAL_OFFER_CONFLICT_EXISTS
    if normalized_error_code in {
        "special_offer_invalid_course_count",
        "special_offer_source_invalid_media",
        "special_offer_invalid_id",
        "special_offer_invalid_teacher_id",
        "special_offer_invalid_price_amount",
    }:
        return SPECIAL_OFFER_INVALID_INPUT
    if normalized_error_code == "special_offer_ready_transition_failed":
        if is_regenerate:
            return SPECIAL_OFFER_REGENERATE_FAILED
        return SPECIAL_OFFER_GENERATE_FAILED
    if normalized_error_code == "special_offer_domain_unavailable":
        return SPECIAL_OFFER_GENERATE_FAILED
    return None


__all__ = [
    "SPECIAL_OFFER_CONFLICT_EXISTS",
    "SPECIAL_OFFER_GENERATE_FAILED",
    "SPECIAL_OFFER_GENERATE_SUCCESS",
    "SPECIAL_OFFER_INVALID_INPUT",
    "SPECIAL_OFFER_NO_OUTPUT_TO_REGENERATE",
    "SPECIAL_OFFER_OVERWRITE_CONFIRMATION",
    "SPECIAL_OFFER_REGENERATE_FAILED",
    "SPECIAL_OFFER_REGENERATE_SUCCESS",
    "get_special_offer_error_text_id",
    "get_special_offer_status_text_id",
    "get_special_offer_text",
]
