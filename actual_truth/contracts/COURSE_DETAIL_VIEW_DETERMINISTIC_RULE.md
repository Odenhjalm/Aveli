# COURSE_DETAIL_VIEW DETERMINISTIC RULES

## PURPOSE

This file defines the response-shape guarantees for `CourseDetailResponse`.

This contract operates under `SYSTEM_LAWS.md` and `course_public_surface_contract.md`.
Media representation inside this response operates under `media_unified_authority_contract.md`.
This contract defines no field ownership, semantic meaning, fallback authority, or composition doctrine.

---

## CANONICAL SHAPE

COURSE_DETAIL_VIEW is the `CourseDetailResponse` transport contract.

Top-level serialized field order:

- `course`
- `lessons`
- `short_description`

Rules:

- `course` MUST always exist in the response
- `lessons` MUST always exist in the response
- `short_description` MUST always exist in the response
- Top-level serialization order MUST remain `course`, then `lessons`, then `short_description`
- `cover` MUST NOT exist as a top-level COURSE_DETAIL_VIEW field
- `course` MUST conform to the canonical `CourseDiscoveryCourse` response surface
- `lessons` MUST be serialized as an array
- `short_description` MUST be serialized as `str | null`

---

## SHAPE IMMUTABILITY

The shape of COURSE_DETAIL_VIEW MUST be constant.

Rules:

- All defined fields MUST always exist in the response
- No field may be conditionally added or removed
- Optional fields MUST be present with value = null if missing
- The structure MUST NOT vary between requests

Violation examples:

- Omitting `short_description` when missing
- Returning different field sets between courses

---

## NULLABILITY RULES

Rules:

- Missing optional data MUST be represented as `null`
- Empty string MUST NOT be used instead of `null` for `short_description`
- Field omission is forbidden
- `short_description` MUST be `null` if not present
- `lessons` MUST be `[]` if no lessons exist
- `lessons` MUST NOT be `null`

---

## LESSON ORDERING GUARANTEE

`lessons[]` MUST be deterministically ordered.

Rules:

- MUST be ordered by `position ASC`
- Ordering MUST be stable across identical reads

Violation examples:

- unordered lesson lists
- inconsistent ordering between requests

---

## SERIALIZATION GUARANTEE

Serialization MUST preserve structure exactly.

Rules:

- Output schema MUST match contract exactly
- No hidden transformations
- No field renaming
- No implicit type conversion

---

## VIOLATION CONDITIONS

The contract is violated if:

- field presence varies between responses
- ordering is inconsistent
- missing optional data is omitted instead of serialized as `null`
- `lessons` is returned as `null`
- `cover` appears as a top-level field

---

## SUMMARY

COURSE_DETAIL_VIEW is a deterministic transport projection.

It guarantees:

- stable shape
- fixed field presence
- explicit nullability
- stable lesson ordering
- exact serialization

It is not:

- a domain ownership contract
- a semantic field-definition contract
- a fallback authority contract
- a composition implementation contract
