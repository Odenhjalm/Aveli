# Login System Overview & Google Sign-In Status

## Frontend auth setup (Flutter web)
- Config source: single `frontend/.env` (fallback `frontend/env/.env`), keys used at runtime: `SUPABASE_URL`, `SUPABASE_PUBLIC_API_KEY`. Dart-defines override if provided. No APP_ENV switching.
- Supabase init: `Supabase.initialize` in `lib/main.dart` with PKCE auth flow, using `EnvResolver.supabaseUrl` / `supabasePublicApiKey`.
- OAuth start: `AuthRepository.startOAuthSignIn` -> `supabase.auth.signInWithOAuth` with redirectTo built per platform. Web redirect is `http://localhost:4003/login-callback` (includes `provider` and optional `redirect` params).
- Callback handling:
  - Route `/login-callback` renders `OAuthCallbackScreen`, which calls `getSessionFromUrl(Uri.base, storeSession: true)`, then exchanges the Supabase session with backend `/auth/oauth`, and routes to home or onboarding.
  - Deep links (mobile/webviews) also call `getSessionFromUrl(..., storeSession: true)` in `DeepLinkService` before forwarding to `/login-callback`.
- Auth state/guards: `AuthController` listens to Supabase `onAuthStateChange` and finalizes sessions; GoRouter uses `RouteSessionSnapshot` to gate private routes.

## Backend reflection
- The frontend exchanges Supabase sessions via backend endpoints: `/auth/oauth` (for social login exchange), `/auth/login`, `/auth/register`, `/auth/me` etc., using tokens saved in `TokenStorage`.
- Backend expects a reachable API base URL (default in code is `http://127.0.0.1:8080` unless overridden). If backend is not running at that address, frontend logs `DioException [connection error]` for API calls.
- Supabase JWT verification in backend has been migrated to RS256 JWKS and no longer relies on a local JWT secret; Supabase project keys must stay aligned with frontend `.env` values.

## Google sign-in problem (detailed)
- Symptom: On web, after Google redirect the app returned to landing and Supabase logs showed `AuthException(User not found, server_error)`; sessions were not persisted.
- Root causes addressed:
  1) Callback handling previously called `getSessionFromUrl` without `storeSession: true`, so Supabase never saved the session. Added `storeSession: true` in both callback screen and deep link handler.
  2) Multiple env files / APP_ENV logic could point Chrome builds at the wrong Supabase project. Simplified to a single `.env` to remove ambiguity.
- Remaining prerequisites for successful login:
  - Backend must be running and reachable at the configured `API_BASE_URL` (default 127.0.0.1:8080); otherwise API exchanges fail with connection errors.
  - Supabase Google provider redirect must include `http://localhost:4003/login-callback`.
  - `.env` must contain valid `SUPABASE_URL`/`SUPABASE_PUBLIC_API_KEY` (already present) and optional Stripe keys if you want to remove the red banner.

## What to check next (manual)
1) Start backend where `API_BASE_URL` points (or set it via dart-define/`.env`).
2) Run `flutter run -d chrome --web-port=4003`.
3) Click “Continue with Google”, complete consent.
4) Verify `/login-callback` shows briefly, then routes to the logged-in UI; check console logs for `OAuth getSessionFromUrl session=...` and that no `connection error` logs remain.
