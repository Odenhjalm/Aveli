# Canonical vs Non-Authoritative Boundary

## Purpose

This document protects the locked canonical baseline authority from accidental attack during the upcoming large outrooting effort. It also names the residual surfaces that remain non-authoritative even though they still exist in repository or runtime-adjacent code.

## Locked Canonical Baseline Authority

The following are authoritative and are not drift targets for the outrooting tree:

1. `backend/supabase/baseline_slots/` as the canonical local baseline source of truth.
2. `backend/supabase/baseline_slots.lock.json` as the slot lock and hash boundary.
3. Protected historical slots `0001` through `0012`.
4. Accepted append-only authority extensions `0013` through `0019`.
5. The canonical source documents:
   - `Aveli_System_Decisions.md`
   - `aveli_system_manifest.json`
   - `AVELI_DATABASE_BASELINE_MANIFEST.md`
   - `NEW_BASELINE_DESIGN_PLAN.md`
   - active contracts under `actual_truth/contracts/`
   - `codex/AVELI_OPERATING_SYSTEM.md`
   - `codex/AVELI_EXECUTION_POLICY.md`
   - `codex/AVELI_EXECUTION_WORKFLOW.md`
6. The aggregate completion result `FINAL_CANONICAL_BASELINE_COMPLETION_LOCKED` in `BCP-051_aggregate_canonical_authority_completion.md`.

## What Canonical Authority Means Here

- `memberships` is canonical app-entry authority.
- `auth_subjects` is canonical onboarding, role, and admin authority.
- `runtime_media` is the only runtime truth layer for governed media surfaces.
- Backend read composition is the sole authority for frontend media representation.
- `profile_media_placements` is the only authored-placement source entity for the profile-media feature domain.
- The append-only baseline slot chain, not remote-schema history, defines the authoritative local verification database.

## Non-Authoritative Residual Drift

The following are eligible outrooting targets because they remain outside locked canonical authority:

1. Compatibility logic that preserves Stripe-era membership assumptions after app-entry authority was canonically moved to `app.memberships`.
2. Remote-schema and legacy migration lineage that still encode old profile, teacher-rights, fallback, storage, or retired entity doctrine.
3. Raw-table lesson and lesson-media helpers that remain outside final mounted read authority.
4. Legacy home-audio playback-shaping code paths that sit beside the canonical runtime path.
5. Cleanup and migration residue that still references retired `teacher_profile_media` doctrine.
6. Legacy payload fields such as `asset_url`, `cover_url`, `fallback_policy`, or `legacy_storage_*` outside canonical runtime and read-composition boundaries.

## Explicit Boundary Rules For Future Outrooting

1. Do not treat repository presence as authority. Legacy code can exist without being canonical.
2. Do not attack append-only baseline slots because an older slot still contains superseded substrate expressions. Locked canonical history remains protected.
3. Do not attack canonical files merely because a filename is legacy-shaped if the mounted behavior has already been aligned to canonical truth.
4. Do not treat `supabase/migrations/*.sql` as authoritative local baseline truth. They remain production migration history only.
5. Do not classify active canonical contracts as legacy just because they constrain or supersede older runtime behavior.

## Known Boundary Examples

### Protected Canonical

- `backend/supabase/baseline_slots/0013_memberships_core.sql`
- `backend/supabase/baseline_slots/0014_auth_subjects_core.sql`
- `backend/supabase/baseline_slots/0017_runtime_media_unified.sql`
- `backend/supabase/baseline_slots/0018_runtime_media_home_player.sql`
- `backend/supabase/baseline_slots/0019_runtime_media_profile_media.sql`

These are accepted append-only baseline authority additions and must not be treated as legacy cleanup targets.

### Residual Non-Authoritative

- `backend/supabase/migrations/20260320075542_remote_schema.sql`
- `backend/supabase/migrations/20260331_profile_media_identity_cleanup.sql`
- `backend/app/services/home_audio_service.py`
- `backend/app/repositories/memberships.py` compatibility branches
- `backend/app/repositories/courses.py` raw-table helper paths
- `backend/app/models.py` cleanup references to `app.teacher_profile_media`
- `backend/app/routes/studio.py` legacy `asset_url` write residue

These remain relevant outrooting targets because they are not the locked canonical path.

## Safe Interpretation Rule

If a surface conflicts with the locked baseline slot chain or active canonical contracts, interpret the surface as non-authoritative residual drift unless it was explicitly canonized later in the append-only authority path.
