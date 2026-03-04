# OAuth Frontend Fix Report

## Files modified
- frontend/.env
- frontend/env/.env (legacy mirror only)
- frontend/lib/core/env/env_resolver.dart
- frontend/lib/main.dart
- frontend/lib/api/auth_repository.dart
- frontend/lib/core/auth/auth_controller.dart
- frontend/lib/core/deeplinks/deep_link_service.dart
- frontend/lib/features/auth/presentation/oauth_callback_screen.dart
- frontend/lib/features/community/presentation/teacher_profile_page.dart
- frontend/lib/features/studio/presentation/profile_media_page.dart

## Env simplification
- Development now reads a single `.env` in `frontend/` (fallback `env/.env`), carrying only `SUPABASE_URL` and `SUPABASE_PUBLIC_API_KEY`.
- Removed APP_ENV switching; `EnvResolver` just pulls dart-defines or `.env` values. Legacy env files are marked placeholders to avoid accidental use.

## OAuth flow fixes
- Google redirect explicitly targets `http://localhost:4003/login-callback` on web (with provider + redirect params).
- `/login-callback` GoRoute renders `OAuthCallbackScreen`, which invokes `getSessionFromUrl(Uri.base, storeSession: true)` before exchanging the session and routing to home/onboarding.
- Deep links on mobile/webviews also call `getSessionFromUrl(..., storeSession: true)` and forward to `/login-callback` with redirect/provider preserved.
- Added callback logging to make failures visible in dev output.

## Verification
- `flutter analyze` now passes with zero issues.

## Follow-ups
- When production hardening is needed, reintroduce environment layering/flavors with explicit `.env` separation but keep the web build defaults aligned with backend Supabase settings.
