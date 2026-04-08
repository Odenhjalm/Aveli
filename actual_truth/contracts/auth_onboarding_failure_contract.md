# Auth + Onboarding Failure Contract

## STATUS

ACTIVE

This contract defines the single canonical failure envelope for Auth + Onboarding execution surfaces.
This contract composes with `auth_onboarding_contract.md`.

## 1. SCOPE

This contract applies only to the following surfaces:

- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/forgot-password`
- `POST /auth/reset-password`
- `POST /auth/refresh`
- `POST /auth/send-verification`
- `GET /auth/verify-email`
- `GET /auth/validate-invite`
- `POST /auth/onboarding/complete`
- `GET /profiles/me`
- `PATCH /profiles/me`
- `POST /admin/users/{user_id}/grant-teacher-role`
- `POST /admin/users/{user_id}/revoke-teacher-role`

This contract does not redefine failure semantics for referral redemption, commerce, or media surfaces.

## 2. CANONICAL ERROR ENVELOPE

The only allowed error response shape is:

`{ "status": "error", "error_code": string, "message": string, "field_errors"?: [{ "field": string, "error_code": string, "message": string }] }`

Rules:

- `status` is required and MUST equal `"error"`.
- `error_code` is required.
- `message` is required.
- `field_errors` is optional.
- `field_errors` entries may contain only:
  - `field`
  - `error_code`
  - `message`

## 3. FORBIDDEN ERROR SHAPES

The following fields are forbidden on covered surfaces:

- `detail`
- `error`
- `description`
- raw framework exception payloads
- alternative top-level arrays
- mixed success-and-error payloads

## 4. LANGUAGE POLICY

- `error_code` MUST be stable English `snake_case`.
- `message` MUST be Swedish.
- `field_errors[].error_code` MUST be stable English `snake_case`.
- `field_errors[].message` MUST be Swedish.
- Frontend may render from `message` or map from `error_code`, but MUST NOT depend on forbidden legacy fields.

## 5. HTTP STATUS TO DOMAIN ERROR MAPPING

### `400 Bad Request`

- `invalid_or_expired_token`
- `invalid_current_password`
- `new_password_must_differ`

### `401 Unauthorized`

- `invalid_credentials`
- `unauthenticated`
- `refresh_token_invalid`

### `403 Forbidden`

- `forbidden`
- `admin_required`

### `404 Not Found`

- `user_not_found`
- `subject_not_found`
- `profile_not_found`

### `409 Conflict`

- `email_already_registered`
- `already_teacher`
- `already_learner`
- `admin_bootstrap_already_consumed`

### `422 Unprocessable Entity`

- `validation_error`

### `429 Too Many Requests`

- `rate_limited`

### `500 Internal Server Error`

- `internal_error`

## 6. FIELD-LEVEL VALIDATION RULE

- `field_errors` is allowed only when the failure is a validation failure.
- `field_errors` MUST identify only request fields owned by the target route.
- `field_errors` MUST NOT introduce alternative error authority outside `error_code`.

## 7. FINAL ASSERTION

- This contract is the only canonical failure envelope for Auth + Onboarding surfaces.
- Covered surfaces MUST NOT emit ambiguous legacy error payloads.
