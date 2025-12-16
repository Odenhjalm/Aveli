# Archive

Items parked during MVP stabilization to keep the working tree clean while preserving context.

- `archive/experiments/`
  - `codex_output/`: prior Codex/OAuth investigation reports and patches.
  - `ops_reports/`: auth/env/schema drift reports from automated audits.
  - `backend_ops_reports/`: backend sanitize run reports moved out of the live tree.
- `archive/drafts/`
  - `USER_ACCOUNTS.md`: potentially sensitive account notes, kept out of the active repo.
  - `google_sign_in_tasks.md`: draft task list for Google sign-in work.
  - `new_oauth.md`: exploratory OAuth migration notes.
  - `task.md`: scratchpad tasks.
  - `localization/en.arb` + `localization/sv.arb`: legacy empty ARB files that broke `flutter pub get`; kept for reference only.
- `archive/old_auth/`
  - `026_profile_provider_fields.sql`: legacy/duplicate Supabase migration held to avoid accidental application.

Nothing here is part of the MVP surface area; restore selectively if needed.
