# STUDIO SESSIONS EDGE CONTRACT

## STATUS

ACTIVE

This contract operates under `SYSTEM_LAWS.md`.
This contract contains response-shape law only.

## STUDIO SESSION OUTPUT SHAPE

`StudioSession` final serialized field order:

- `id`
- `teacher_id`
- `title`
- `description`
- `start_at`
- `end_at`
- `capacity`
- `price_cents`
- `currency`
- `visibility`
- `recording_url`
- `stripe_price_id`
- `created_at`
- `updated_at`

Field rules:

- `id` MUST be present and MUST be `UUID`
- `teacher_id` MUST be present and MUST be `UUID`
- `title` MUST be present and MUST be `str`
- `description` MUST be present and MUST be `str | null`
- `start_at` MUST be present and MUST be `datetime | null`
- `end_at` MUST be present and MUST be `datetime | null`
- `capacity` MUST be present and MUST be `int | null`
- `price_cents` MUST be present and MUST be `int`
- `currency` MUST be present and MUST be `str`
- `visibility` MUST be present and MUST be `"draft" | "published"`
- `recording_url` MUST be present and MUST be `str | null`
- `stripe_price_id` MUST be present and MUST be `str | null`
- `created_at` MUST be present and MUST be `datetime`
- `updated_at` MUST be present and MUST be `datetime`
- Field omission is forbidden for all listed `StudioSession` fields

## STUDIO SESSION SLOT OUTPUT SHAPE

`SessionSlotResponse` serialized field order:

- `id`
- `session_id`
- `start_at`
- `end_at`
- `seats_total`
- `seats_taken`
- `created_at`
- `updated_at`

Field rules:

- `id` MUST be present and MUST be `UUID`
- `session_id` MUST be present and MUST be `UUID`
- `start_at` MUST be present and MUST be `datetime`
- `end_at` MUST be present and MUST be `datetime`
- `seats_total` MUST be present and MUST be `int`
- `seats_taken` MUST be present and MUST be `int`
- `created_at` MUST be present and MUST be `datetime`
- `updated_at` MUST be present and MUST be `datetime`
- Field omission is forbidden for all listed `SessionSlotResponse` fields

## TRANSPORT CONSTRAINTS

- Response payloads MUST preserve the listed field names exactly
- `price_amount_cents` MUST NOT be emitted as contract output
- `published` MUST NOT be emitted as contract output
- Raw map transport wrappers MUST NOT be emitted as contract output
