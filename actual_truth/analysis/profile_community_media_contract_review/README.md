## Profile/Community Media Contract Review

### Purpose

This directory contains a full no-code canonical review of the current `PROFILE COMMUNITY MEDIA CONTRACT` candidate in:

- `actual_truth/contracts/profile_community_media_contract.md`

The review compares the document against:

- the full canonical doctrine set
- the current baseline status and accepted baseline slots
- the current `BCP-043` blocker context

### Review Scope

This review included:

- `Aveli_System_Decisions.md`
- `aveli_system_manifest.json`
- `AVELI_DATABASE_BASELINE_MANIFEST.md`
- `NEW_BASELINE_DESIGN_PLAN.md`
- the contract set under `actual_truth/contracts/`
- `codex/AVELI_OPERATING_SYSTEM.md`
- `codex/AVELI_EXECUTION_POLICY.md`
- `codex/AVELI_EXECUTION_WORKFLOW.md`
- `backend/supabase/baseline_slots/`
- `backend/supabase/baseline_slots.lock.json`
- the `BCP-043` blocker artifact and the earlier proposal analysis artifacts

### Current Baseline Reality Considered

The review treated the current accepted baseline as the target authority layer below any future profile/community feature contract.

Important current baseline facts:

- `0013_memberships_core.sql` defines app-entry authority only
- `0014_auth_subjects_core.sql` defines onboarding, role, and admin authority only
- `0017_runtime_media_unified.sql` materializes runtime truth only for lesson media and course cover
- `0018_runtime_media_home_player.sql` extends runtime truth only for home-player direct-upload media
- no accepted baseline slot currently defines a profile/community source model
- no accepted baseline slot currently defines profile/community-specific `media_purpose` values

### Review Outcome

The current document contains a strong canonical core, but it also hard-codes multiple source-shape decisions that are not yet declared elsewhere in the canonical source set.

The strongest review conclusion is:

- the document should not be treated as an active contract
- the document is best treated as a `DECISION_SCAFFOLD`
- the minimum safe revision is to preserve already-declared doctrine and downgrade unsupported source-shape choices into explicit unresolved decisions

### Files

- `CHANGE_PROPOSALS.md`
- `CANONICAL_ALIGNMENT_MATRIX.md`
- `FINAL_JUDGMENT.md`
