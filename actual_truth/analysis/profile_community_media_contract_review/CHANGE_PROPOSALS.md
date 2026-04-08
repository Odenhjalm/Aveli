## Change Proposals

### PCM-001

- `change_id`: `PCM-001`
- `current_section`: `Document header + STATUS + Section 1`
- `proposed_change`: Rewrite the document role so it no longer behaves like a provisional active contract. The document should explicitly say it contains two layers only: already-declared doctrine and unresolved decisions that cannot yet drive implementation.
- `change_type`: `REWRITE`
- `why_this_change_is_needed`: The document sits inside `actual_truth/contracts/`, which the operating system and execution policy treat as the authoritative contract set. A candidate that mixes active doctrine with speculative source-shape choices is too easy to misread as usable truth.
- `canonical_support`:
  - `codex/AVELI_OPERATING_SYSTEM.md`: `actual_truth/contracts/` is the only authoritative contract set
  - `codex/AVELI_EXECUTION_POLICY.md`: anything defined in `contracts/` is an instruction, not a question
  - existing contract-set practice: contracts use explicit status and lock semantics
- `classification`:
  - `canonical_strength`: `HIGH`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: This reduces the chance that teacher-facing or learner-facing flows are accidentally aligned to undeclared source truth. It protects editor access, media upload flows, course-selling flows, and learner-access flows from inheriting a second media authority by mistake.
- `decision_status`: `ALREADY_DECLARED_AND_SHOULD_BE_STRENGTHENED`

### PCM-002

- `change_id`: `PCM-002`
- `current_section`: `Missing section`
- `proposed_change`: Add a section called `Current Canonical Doctrine` that records only already-declared rules: profile/community media is a governed media usage, `runtime_media` is runtime truth, backend read composition is the sole frontend representation authority, non-core feature truth must not be embedded into baseline core, and storage/fallback/map/blob truth is forbidden.
- `change_type`: `ADD`
- `why_this_change_is_needed`: The current document jumps from purpose into source-shape choices without clearly separating what is already canonical from what is still unsettled.
- `canonical_support`:
  - `Aveli_System_Decisions.md`: feature contract expansion rules and canonical media model
  - `aveli_system_manifest.json`: `explicit_structured_contract_required`, `runtime_truth_authority`, `runtime_media_bypass_forbidden`
  - `actual_truth/contracts/media_unified_authority_contract.md`
  - `actual_truth/contracts/profile_media_edge_contract.md`
- `classification`:
  - `canonical_strength`: `HIGH`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: This anchors the document in the same media doctrine already used by course, lesson, and home-player surfaces, which supports stable teacher upload flows and learner access flows without introducing surface-specific exceptions.
- `decision_status`: `ALREADY_DECLARED_AND_SHOULD_BE_STRENGTHENED`

### PCM-003

- `change_id`: `PCM-003`
- `current_section`: `Section 4. Candidate Source Entity`
- `proposed_change`: Split the section into two parts:
  - `Declared Doctrine`: a separate typed feature-specific source model above baseline core is required
  - `Unresolved Decisions`: entity name, entity count, and one-model-vs-two-model decision
- `change_type`: `SPLIT`
- `why_this_change_is_needed`: The current section correctly states that the feature domain needs its own typed source model, but it overreaches by locking one shared model and a concrete entity name.
- `canonical_support`:
  - `Aveli_System_Decisions.md`: profile media is a separate feature domain and needs an explicit structured contract
  - `AVELI_DATABASE_BASELINE_MANIFEST.md`: non-core feature domains are not directly defined in baseline core
  - `NEW_BASELINE_DESIGN_PLAN.md`: profile media is not part of canonical baseline core here
- `classification`:
  - `canonical_strength`: `HIGH`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: This preserves the system law that teacher/editor/community features must not smuggle feature truth into core tables, while avoiding premature choices that could later distort course, payment, or learner-access models.
- `decision_status`: `ALREADY_DECLARED_AND_SHOULD_BE_STRENGTHENED`

### PCM-004

- `change_id`: `PCM-004`
- `current_section`: `Section 4. Candidate Source Entity`
- `proposed_change`: Remove the explicit shared entity name `profile_community_media` and downgrade the one-shared-model choice into an unresolved decision that requires a real canonical declaration before activation.
- `change_type`: `DOWNGRADE_TO_UNRESOLVED_DECISION`
- `why_this_change_is_needed`: No active canonical document or accepted baseline slot currently names that entity or locks the one-model decision.
- `canonical_support`:
  - absence across `Aveli_System_Decisions.md`, `aveli_system_manifest.json`, `AVELI_DATABASE_BASELINE_MANIFEST.md`, `NEW_BASELINE_DESIGN_PLAN.md`, and accepted baseline slots
  - contrast with `actual_truth/contracts/studio_sessions_edge_contract.md`, which shows what a fully declared explicit non-core contract looks like when the source set really does lock the shape
- `classification`:
  - `canonical_strength`: `HIGH`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: This avoids hard-coding a feature-shape decision that might later conflict with teacher profile flows, community publishing flows, or future studio/community separation without helping learner payment or content-access law.
- `decision_status`: `REQUIRES_EXPLICIT_NEW_DECISION`

### PCM-005

- `change_id`: `PCM-005`
- `current_section`: `Section 5. Authored Identity`
- `proposed_change`: Rewrite the section so it keeps only the parts that are already canonical:
  - media identity remains canonical `app.media_assets.id`
  - authored placement identity must belong to the profile/community feature-specific source model
  - exact subject binding, exact source-row key shape, and publication-state fields remain unresolved decisions
  - remove `app.auth_subjects.user_id` as the chosen authored subject binding
- `change_type`: `DOWNGRADE_TO_UNRESOLVED_DECISION`
- `why_this_change_is_needed`: `auth_subjects` is canonically limited to onboarding, role, and admin authority. The current document overreaches by turning that table into the chosen authored-placement binding for a separate non-core media feature domain.
- `canonical_support`:
  - `AVELI_DATABASE_BASELINE_MANIFEST.md`: `auth_subjects` owns onboarding, role, and admin authority only
  - `actual_truth/contracts/onboarding_teacher_rights_contract.md`: explicit field-level authority for `auth_subjects`
  - `Aveli_System_Decisions.md`: profile media requires its own explicit structured contract
- `classification`:
  - `canonical_strength`: `HIGH`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: This prevents profile/community media from silently broadening auth-subject authority, which protects teacher approval flows, editor permissions, memberships, and learner-content access from cross-domain leakage.
- `decision_status`: `REQUIRES_EXPLICIT_NEW_DECISION`

### PCM-006

- `change_id`: `PCM-006`
- `current_section`: `Section 6. Allowed Purpose Values`
- `proposed_change`: Remove the concrete values `profile_media` and `community_media`. Replace the section with:
  - the currently canonical values already accepted in baseline
  - a statement that profile/community-specific purpose coverage is unresolved and would require an explicit new decision plus append-only baseline authority work
- `change_type`: `DOWNGRADE_TO_UNRESOLVED_DECISION`
- `why_this_change_is_needed`: The current document invents purpose values that are not declared in the canonical source set or current baseline.
- `canonical_support`:
  - `backend/supabase/baseline_slots/0001_canonical_foundation.sql`: `course_cover`, `lesson_media`
  - `backend/supabase/baseline_slots/0018_runtime_media_home_player.sql`: `home_player_audio`
  - `AVELI_DATABASE_BASELINE_MANIFEST.md`: `home_player_audio` is explicitly canonical
  - `NEW_BASELINE_DESIGN_PLAN.md`: baseline purpose set and later home-player extension
- `classification`:
  - `canonical_strength`: `HIGH`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: This avoids a premature purpose taxonomy that could fragment the unified media domain or create migration debt across teacher upload, community presentation, and learner-facing rendering.
- `decision_status`: `REQUIRES_EXPLICIT_NEW_DECISION`

### PCM-007

- `change_id`: `PCM-007`
- `current_section`: `Sections 7 and 11`
- `proposed_change`: Rewrite these sections together so they explicitly distinguish:
  - current baseline truth
  - future canonical extension path

  The revised wording should state that current accepted baseline truth materializes profile/community doctrine only indirectly through global media law, while current `runtime_media` rows exist only for lesson media, course cover, and home-player direct uploads.
- `change_type`: `REWRITE`
- `why_this_change_is_needed`: The current wording is doctrinally correct but too close to present-tense implementation truth. It understates the fact that the current baseline does not yet provide profile/community source or runtime rows.
- `canonical_support`:
  - `AVELI_DATABASE_BASELINE_MANIFEST.md`: profile media is non-core; `runtime_media` is runtime truth
  - `backend/supabase/baseline_slots/0017_runtime_media_unified.sql`
  - `backend/supabase/baseline_slots/0018_runtime_media_home_player.sql`
  - `baseline_slots.lock.json`
- `classification`:
  - `canonical_strength`: `HIGH`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: This makes it clearer that profile/community work must remain append-only and must not distort existing teacher/editor/course/learner core behavior while still preserving a path for future governed media support.
- `decision_status`: `ALREADY_DECLARED_AND_SHOULD_BE_STRENGTHENED`

### PCM-008

- `change_id`: `PCM-008`
- `current_section`: `Sections 8 and 9`
- `proposed_change`: Strengthen the backend-boundary and forbidden-field sections by directly importing already-declared prohibitions:
  - repositories must not resolve media
  - repositories must not expose media URLs
  - routes must not construct media outside backend read composition
  - add explicit forbidden legacy fields and shapes such as `cover_url`, `image_url`, `playback_url`, `signed_url_expires_at`, and `preferredUrl`
- `change_type`: `UPGRADE_TO_CANONICAL_DOCTRINE`
- `why_this_change_is_needed`: The current document is directionally correct but not yet as strong as the active unified media doctrine and execution policy.
- `canonical_support`:
  - `actual_truth/contracts/media_unified_authority_contract.md`
  - `actual_truth/contracts/media_image_edge_contract.md`
  - `actual_truth/contracts/landing_edge_contract.md`
  - `codex/AVELI_EXECUTION_POLICY.md`
- `classification`:
  - `canonical_strength`: `HIGH`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: This better protects every teacher-facing and learner-facing media surface from fallback URL truth, making future profile/community support safer without destabilizing the existing course and membership model.
- `decision_status`: `ALREADY_DECLARED_AND_SHOULD_BE_STRENGTHENED`

### PCM-009

- `change_id`: `PCM-009`
- `current_section`: `Section 10. Mounted Surface Implications`
- `proposed_change`: Remove concrete surface examples such as teacher profile surfaces and community-facing media surfaces. Rewrite the section in generic canonical terms: any mounted profile/community surface must consume unified media truth through backend read composition and must not create a second resolver path.
- `change_type`: `REWRITE`
- `why_this_change_is_needed`: The examples are drawn from blocker and runtime context rather than from explicit canonical documents. The examples are plausible, but they are not yet the canonically declared surface inventory.
- `canonical_support`:
  - `actual_truth/contracts/media_unified_authority_contract.md`
  - `actual_truth/contracts/profile_media_edge_contract.md`
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-043_align_read_composition_to_unified_runtime_media.md` for blocker context only, not authority
- `classification`:
  - `canonical_strength`: `MEDIUM`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: This keeps the contract stable even if future product surfaces change, while still protecting teacher/community media handling from resolver drift.
- `decision_status`: `SHOULD_BE_REMOVED_AS_NONCANONICAL`

### PCM-010

- `change_id`: `PCM-010`
- `current_section`: `Section 12. Canonical Acceptance Rule`
- `proposed_change`: Replace the current activation rule with an explicit `Unresolved Decisions Required Before Activation` section that lists:
  - source entity name or names
  - one-model versus separate-model choice
  - authored subject binding
  - publication-state fields
  - profile/community-specific purpose coverage
  - append-only baseline path required to materialize runtime truth
- `change_type`: `REWRITE`
- `why_this_change_is_needed`: The current section is correct in spirit but too abstract. The blocker at `BCP-043` is exactly caused by those still-unresolved decisions.
- `canonical_support`:
  - `Aveli_System_Decisions.md`: explicit structured contract required
  - `aveli_system_manifest.json`: profile-media contract rules
  - `actual_truth/analysis/profile_community_media_contract_proposal/VERIFICATION_AGAINST_CANONICAL_SOURCES.md`
  - `actual_truth/analysis/profile_community_media_contract_proposal/DECISION_STATUS.md`
- `classification`:
  - `canonical_strength`: `HIGH`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: This directly protects the Aveli target model by preventing profile/community media work from re-entering implementation before its authority model is actually declared.
- `decision_status`: `ALREADY_DECLARED_AND_SHOULD_BE_STRENGTHENED`

## Minimum Edit Set

The smallest edit set that would most improve the document without inventing truth is:

1. Rewrite the header and Section 1 so the file is clearly a doctrine-plus-decision scaffold rather than a provisional active contract.
2. Add a `Current Canonical Doctrine` section.
3. Split Section 4 and downgrade the chosen entity name and one-model choice into unresolved decisions.
4. Rewrite Section 5 so it no longer picks `app.auth_subjects.user_id` as the authored subject binding.
5. Rewrite Section 6 so it no longer invents `profile_media` and `community_media` purpose values.
6. Rewrite Sections 7 and 11 to include current baseline reality.
7. Replace Section 12 with an explicit unresolved-decision activation gate.

## Best Future-Proof Version

The strongest long-term document shape is:

1. `Status And Document Role`
2. `Current Canonical Doctrine`
3. `Current Baseline Status`
4. `Profile/Community Media Boundary Law`
5. `Explicit Unresolved Decisions`
6. `Activation Criteria Before This Can Become Active Truth`

In that future-proof version:

- already-declared doctrine is explicit and stable
- unresolved source-shape choices are explicit but non-operative
- baseline reality is recorded precisely
- implementation can safely derive work only after the unresolved decisions become real canonical truth
