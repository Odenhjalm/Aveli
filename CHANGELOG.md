# Changelog

## 2024-10-03
- Hardened local backend authentication with refresh-token rotation, rate limiting, and audit logging (`app.refresh_tokens`, `app.auth_events`).
- Added community/messaging pytest coverage and consolidated Flutter UUID parsing to accept any UUID version.
- Introduced versioned SQL migrations and snapshot tooling (`scripts/create_db_snapshot.sh`).
- Enhanced QA smoke test with refresh verification and ensured CI runs backend tests alongside Flutter tasks.
- Added Flutter repository integration test covering login → studio → course checkout.
