# BCP-041

- TASK_ID: `BCP-041`
- TYPE: `GATE`
- TITLE: `Lock the unified runtime_media boundary before append-only media work starts`
- PROBLEM_STATEMENT: `Append-only media work cannot start until the resolved runtime_media boundary proves that course cover, lesson media, and other governed surfaces can use one runtime truth chain without collapsing authored identity or frontend representation into runtime_media itself.`
- IMPLEMENTATION_SURFACES:
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-040_resolve_unified_runtime_media_expansion.md`
  - `actual_truth/contracts/media_unified_authority_contract.md`
  - `actual_truth/contracts/COURSE_COVER_READ_CONTRACT.md`
  - `backend/supabase/baseline_slots/0008_runtime_media_projection_core.sql`
- TARGET_STATE:
  - one resolved runtime-media boundary exists
  - authored identity owners and runtime truth remain distinct
  - course cover no longer requires a separate resolver doctrine
  - downstream baseline work can expand `runtime_media` append-only without guessing coverage or fields
- DEPENDS_ON:
  - `BCP-040`
- VERIFICATION_METHOD:
  - assert one authority chain for governed media surfaces
  - assert `runtime_media` is runtime truth only, not frontend representation
  - stop if any governed surface still requires a parallel media truth path

## GATE ASSERTIONS

- One media authority chain exists for governed media surfaces in scope:
  - `media_id -> runtime_media -> backend read composition -> API -> frontend`
- `app.runtime_media` remains runtime truth only:
  - owns media state and resolution eligibility only
  - does not own authored identity
  - does not own frontend representation
- Authored identity owners remain distinct:
  - lesson media authored placement = `app.lesson_media`
  - course-cover pointer identity = `app.courses.cover_media_id`
- Active baseline-owned runtime row sources in current scope are only:
  - lesson media
  - course cover
- No separate cover-resolver doctrine remains in the locked boundary.
- Non-porting runtime fields remain outside the locked boundary:
  - `reference_type`
  - `auth_scope`
  - `fallback_policy`
  - `home_player_upload_id`
  - `teacher_id`
  - `media_object_id`
  - legacy storage fields
  - `kind`
- Home-player direct uploads and profile/community media do not become baseline-owned runtime row sources in this task; they remain subordinate future or downstream consumers that must attach to the same authority chain when canonically modeled.

## GATE EVIDENCE

- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-040_resolve_unified_runtime_media_expansion.md`
  - already resolves the current-scope row model
  - already keeps authored identity separate from runtime truth
  - already excludes non-porting runtime fields and alternate media paths
- `actual_truth/contracts/media_unified_authority_contract.md`
  - fixes one authority chain only
  - fixes backend read composition as the sole frontend-representation authority
  - forbids cover-specific authority and frontend media construction
- `actual_truth/contracts/COURSE_COVER_READ_CONTRACT.md`
  - fixes `app.courses.cover_media_id` as pointer-only identity
  - requires `cover` to derive from canonical runtime truth in `app.runtime_media`
- `NEW_BASELINE_DESIGN_PLAN.md`
  - requires `runtime_media` to include `playback_object_path` and `playback_format`
  - explicitly non-ports `reference_type`, `auth_scope`, `fallback_policy`, `home_player_upload_id`, `teacher_id`, `media_object_id`, legacy storage fields, and `kind`
- `backend/supabase/baseline_slots/0008_runtime_media_projection_core.sql`
  - demonstrates the protected lesson-only baseline that must be superseded append-only rather than mutated in place
- repo mismatch evidence only:
  - `backend/app/services/courses_service.py` still contains separate course-cover resolution logic, which confirms mounted drift but does not invalidate the locked boundary itself

## GATE DECISION

- The unified runtime-media boundary is deterministic enough for append-only baseline ownership work to proceed.
- Course cover no longer requires a separate resolver doctrine inside the locked boundary.
- Authored identity and runtime truth remain materially distinct.
- Mounted runtime drift remains a later alignment concern and does not block `BCP-042` because the canonical boundary no longer depends on those drift paths for definition.

## EXECUTION LOCK

- EXPECTED_GATE_STATE:
  - downstream append-only media work may expand `runtime_media` without guessing field scope, ownership, or cover semantics
  - no parallel media-truth doctrine survives in the locked boundary
- ACTUAL_GATE_STATE_BEFORE_ACTION:
  - `BCP-040` had resolved the boundary, but this gate artifact had not yet certified that append-only media work could begin safely
  - protected slot `0008` and mounted course-cover logic still reflected legacy lesson-only or special-case drift
- DECISION:
  - gate passes
- REMAINING_RISKS:
  - append-only unified runtime-media ownership still must land in `BCP-042`
  - mounted runtime still contains separate cover-resolution logic until `BCP-043`
- LOCK_STATUS:
  - `PASSED_FOR_BCP-042`
