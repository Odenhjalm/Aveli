# Google Sign-In Stabilization – Work Plan

Goal: Google OAuth (web + mobile) returns a Supabase session, exchanges it via `/auth/oauth`, and persists login across reloads.

## Execution Checklist
- [x] **Supabase env delivery on web** — Decide delivery path: (a) `flutter run -d chrome --web-port=4003 --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_API_KEY=...` or (b) bundle `env/.env` asset; ensure `frontend/env/.env` contains the correct project keys (publishable URL/key) and remove placeholder URLs. _Status: `frontend/env/.env` added with Supabase URL/publishable API key, API base, and OAuth redirects for local web/mobile; keep in sync with the target Supabase project._
- [x] **Runtime verification** — Log the resolved Supabase URL + public key prefix in `frontend/lib/core/env/env_resolver.dart` or `frontend/lib/main.dart` (debug-only) to confirm the app points at the intended Supabase project when running on web. _Status: debug log added in `frontend/lib/main.dart` redacting public key._
- [ ] **Supabase dashboard settings** — Confirm Google provider is enabled with valid client ID/secret; allow sign-ups; whitelist exact redirect(s): `http://localhost:4003/login-callback` for local and the production callback URL.
- [x] **OAuth redirect builder** — Align `oauthRedirectWeb` (EnvResolver + defaults in `frontend/lib/main.dart`) with the whitelisted URL; keep PKCE authFlowType in `Supabase.initialize`. _Status: redirect values set in `frontend/env/.env` to `http://localhost:4003/login-callback` (web) and `aveliapp://auth-callback` (mobile); defaults already match._
- [x] **Callback error handling** — Wrap `getSessionFromUrl` in `frontend/lib/core/auth/auth_controller.dart` and `frontend/lib/core/deeplinks/deep_link_service.dart` with try/catch that logs `error_description`, code, and `Uri.base`; surface a user-friendly message on `OAuthCallbackScreen`. _Status: both handlers now log error/error_description and URI when session recovery fails._
- [x] **Prevent double consumption** — Choose a single handler for web callbacks (either DeepLinkService or `OAuthCallbackScreen`) and gate the other with platform/flag so the auth code/token is consumed once; ensure `storeSession: true` remains. _Status: AuthController skips repeated `getSessionFromUrl` when a session already exists or the URI was handled; DeepLinkService remains mobile-only._
- [ ] **Backend exchange check** — Hit `/auth/oauth` after a successful Supabase session; confirm JWKS URL matches the Supabase project and that returned tokens are stored via `TokenStorage`; log/handle backend errors in `AuthRepository`.
- [ ] **End-to-end test** — With backend running (e.g., `http://localhost:8000`), run the web app with the chosen env method, perform Google login, verify console shows session retrieval, and see `/auth/oauth` 200 in backend logs; reload the app to confirm persistent session.

## Notes
- Keep `EnvResolver` as the single source; avoid mixed env files per environment.
- If web asset loading is chosen, ensure `pubspec.yaml` asset path matches the file (`env/.env`) to prevent 404s.
- Capture findings (errors, logs, Supabase project IDs) in this doc as you progress.
