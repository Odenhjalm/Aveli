# Auth System Rules (Deterministic)

Source of truth for this ruleset:
- `frontend/lib/features/auth/presentation/login_page.dart`
- `frontend/lib/features/auth/presentation/forgot_password_page.dart`
- `frontend/lib/features/auth/presentation/new_password_page.dart`
- `frontend/lib/core/routing/app_router.dart`
- `frontend/lib/core/routing/route_paths.dart`
- `frontend/lib/api/api_paths.dart`
- `frontend/lib/api/auth_repository.dart`
- `frontend/lib/api/api_client.dart`
- `frontend/lib/core/auth/auth_controller.dart`
- `frontend/lib/core/auth/auth_http_observer.dart`
- `frontend/lib/core/auth/token_storage.dart`
- `backend/app/routes/api_auth.py`
- `backend/app/main.py`
- `backend/app/auth.py`
- `backend/app/repositories/auth.py`
- `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`

## RULE 1 — Canonical auth endpoints (mounted runtime)

- Canonical mounted auth router:
  - `backend/app/main.py` includes `api_auth.router`.
- Canonical runtime auth API prefix:
  - `backend/app/routes/api_auth.py` with `APIRouter(prefix="/auth")`.
- Canonical login endpoint:
  - `POST /auth/login` handled by `backend/app/routes/api_auth.py`.
- Canonical refresh endpoint:
  - `POST /auth/refresh` handled by `backend/app/routes/api_auth.py`.
- Canonical password reset request endpoint:
  - `POST /auth/request-password-reset` handled by `backend/app/routes/api_auth.py` and registered as alias path `/auth/request-password-reset` plus `/auth/forgot-password` in same handler.
- Canonical password reset completion endpoint:
  - `POST /auth/reset-password` handled by `backend/app/routes/api_auth.py`.

If a route maps to a non-canonical auth file that is not mounted in `backend/app/main.py`, classify as non-authoritative.

## RULE 2 — Canonical login flow

- If user submits login in `LoginPage`, then `AuthController.login` MUST call:
  - `AuthRepository.login` with `{email, password}`.
- `AuthRepository.login` MUST call API path `ApiPaths.authLogin` with `skipAuth: true`.
- API path `ApiPaths.authLogin` MUST be `/auth/login`.
- Backend `POST /auth/login` MUST:
  - validate user credentials,
  - issue `access_token` and `refresh_token`,
  - persist refresh token via `repositories.upsert_refresh_token`,
  - return a token payload.
- On success:
  - client MUST save both tokens through `TokenStorage.saveTokens`,
  - then fetch `/auth/me`.
- If token persistence or `/auth/me` fails, login is NOT successful and auth state is reset.

## RULE 3 — Canonical refresh flow

- If an authenticated request returns 401 and request is retry-eligible, `ApiClient` MUST attempt `_refreshAccessToken`.
- `_refreshAccessToken` MUST use `TokenStorage.readRefreshToken` and call `POST /auth/refresh` with `skipAuth: true`.
- Backend `POST /auth/refresh` MUST:
  - decode and validate refresh JWT,
  - verify `token_type == "refresh"`,
  - fetch token row from `repositories.get_refresh_token`,
  - reject revoked/rotated/mismatched/expired/missing tokens,
  - rotate token state with `touch_refresh_token_as_rotated`,
  - issue a new access token and new refresh token,
  - persist new refresh token via `upsert_refresh_token`,
  - return a token payload.
- On refresh success, client MUST save new tokens and retry the original request once.
- On refresh failure, client MUST clear stored tokens and emit session-expired behavior.

## RULE 4 — Canonical forgot-password flow

- If user triggers forgot-password form submit, client MUST call `AuthRepository.requestPasswordReset(email)`.
- This call MUST send `POST /auth/request-password-reset` with `skipAuth: true`.
- Backend `POST /auth/request-password-reset` (`request_password_reset`) MUST:
  - apply rate limiting,
  - call email reset dispatch when user exists,
  - return success body `{"status": "ok"}`.
- If request succeeds, frontend SHOULD report confirmation to user; no token is issued.

## RULE 5 — Canonical reset-password flow

- If user opens `/reset-password` with token and submits new password, client MUST call `AuthRepository.resetPassword(token, newPassword)`.
- This call MUST send `POST /auth/reset-password` with `skipAuth: true`.
- Backend `POST /auth/reset-password` MUST call `reset_password_with_token` and:
  - on token error return 400 with `{"error": "invalid_or_expired_token"}`,
  - on success return status result.
- Client behavior after success MUST navigate to `/login` and show success message.

## RULE 6 — Allowed flows

The following MUST be treated as allowed auth flows:
- Login request to `/auth/login`.
- Token refresh via `/auth/refresh` triggered by API interceptor.
- Password reset request via `/auth/request-password-reset`.
- Password reset completion via `/auth/reset-password`.
- Profile hydration via `/auth/me` after login/register.
- Logout clear via local token clear (`TokenStorage.clear`) through `AuthController.logout`.

## RULE 7 — Forbidden/rejected flows

- Any auth flow relying on an unmounted runtime router file is forbidden for runtime behavior (example: endpoints only implemented in unmounted `backend/app/routes/auth.py`).
- Any path not in RULES 2–6 MUST NOT be used as the primary auth execution path.
- Refresh must not proceed without a refresh token present in secure storage.
- Client MUST NOT treat frontend alias confusion as new canonical behavior.
- If refresh fails, session cookies/tokens MUST be cleared and session-expired path executed.

## RULE 8 — Duplicate path conflict handling

- `backend/app/routes/api_auth.py` defines route decorator:
  - `@router.post("/request-password-reset")` and `@router.post("/forgot-password")` on the same handler.
- Canonical route selected for auth flow mapping:
  - `POST /auth/request-password-reset`.
- `POST /auth/forgot-password` is alias-only and MUST NOT be treated as separate primary flow.

## RULE 9 — Flow status matrix

| Flow | Canonical endpoint | Request state | Token mutation | On success | On failure |
| --- | --- | --- | --- | --- | --- |
| login | `POST /auth/login` | unauthenticated | create + persist refresh, return access+refresh | store both tokens, load profile, set authenticated state | clear auth state and emit error |
| refresh | `POST /auth/refresh` | authenticated/expired context | rotate refresh row, issue new tokens | replace stored tokens, retry request | clear tokens, session expired |
| forgot-password | `POST /auth/request-password-reset` | unauthenticated | none | return ok | surface error only |
| reset-password | `POST /auth/reset-password` | unauthenticated | none | return status and route to login | return error payload |

