# OAuth Frontend Analysis

## Environment loading
- `lib/main.dart` now loads a single `.env` (fallback `env/.env`) via `flutter_dotenv`; `EnvResolver` simply reads dart-define overrides or `.env` values (no APP_ENV switching).
- Supabase init uses `EnvResolver.supabaseUrl`/`supabaseAnonKey`; both come from `.env` or dart-define values. Redirect defaults are explicit: web -> `http://localhost:4003/login-callback`, mobile -> `aveliapp://auth-callback`.
- Legacy env files (`frontend/env/.env*`) are no longer used except as a legacy mirror to avoid breakage.

## Supabase OAuth flow (current wiring)
- Sign-in entry: `AuthRepository.startOAuthSignIn` uses `supabase.auth.signInWithOAuth` with redirectTo built from env + provider + optional redirect param.
- Router: `RoutePath.loginCallback` (`/login-callback`) is a dedicated GoRoute that renders `OAuthCallbackScreen`; initialLocation on web respects `Uri.base` (including fragments) so callbacks are not discarded.
- Callback handling: `OAuthCallbackScreen` calls `authController.completeOAuthRedirect`, which now calls `getSessionFromUrl(uri, storeSession: true)` before exchanging the session with backend. Mobile deep links go through `DeepLinkService.handleUri`, which also calls `getSessionFromUrl(..., storeSession: true)` and forwards to the same route.
- Auth guard: route redirects rely on `RouteSessionSnapshot`; after `storeSession: true`, the Supabase session persists so the guard sees an authenticated user.

## Likely failure points observed
- Previous callback handlers called `getSessionFromUrl` without `storeSession: true`, so the Supabase session was never persisted; router then saw no session and bounced back to landing, matching the "User not found" logs.
- Multiple env files + APP_ENV logic risked pointing Chrome builds at the wrong Supabase project. Consolidating to a single `.env` removes that ambiguity.
- No dedicated logging made it hard to see what URI was processed or whether `getSessionFromUrl` succeeded; added debug logs for callback URI and session recovery.
