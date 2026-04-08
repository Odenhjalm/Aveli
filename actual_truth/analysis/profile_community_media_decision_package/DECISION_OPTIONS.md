## Decision Options

### PCM-DEC-001A

- `decision_id`: `PCM-DEC-001A`
- `decision_topic`: `Exact source entity name or names`
- `proposed_value`: `app.profile_media_placements`
- `alternative_values`:
  - `app.profile_community_media_placements`
  - `app.profile_media_placements` plus `app.community_media_placements`
- `why_this_value`: `profile media` is the explicitly named non-core feature domain in the canonical source set. `placements` matches the authored-placement semantics already used elsewhere in the media model without pretending that profile/community media is the same thing as `app.lesson_media`.
- `canonical_support`:
  - `Aveli_System_Decisions.md`: `Profile media is a separate feature domain and must use an explicit structured contract`
  - `Aveli_System_Decisions.md`: `app.media_assets` is media identity and `app.lesson_media` is authored placement
  - `actual_truth/contracts/media_unified_authority_contract.md`: profile/community media is a media usage, not a separate resolver system
- `baseline_interaction`: No current accepted baseline slot defines a profile/community source entity. This value would require a new append-only feature entity above baseline core without mutating existing core entities.
- `classification`:
  - `canonical_strength`: `MEDIUM`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: Keeps teacher-facing and learner-facing core authorities intact while giving profile/community media a dedicated source model that does not distort memberships, auth-subject authority, course access, or lesson media law.
- `risks_if_chosen`: Community-specific publication semantics may later require a second entity or an explicit subtype field.
- `risks_if_not_chosen`: The contract remains blocked on entity naming and no canonical source model can be materialized.

### PCM-DEC-001B

- `decision_id`: `PCM-DEC-001B`
- `decision_topic`: `Exact source entity name or names`
- `proposed_value`: `app.profile_community_media_placements`
- `alternative_values`:
  - `app.profile_media_placements`
  - `app.profile_media_placements` plus `app.community_media_placements`
- `why_this_value`: This option names the grouped profile/community family directly and keeps one obvious place for media placements that feed both profile and community consumers.
- `canonical_support`:
  - `actual_truth/contracts/media_unified_authority_contract.md`: profile/community media is one governed media usage family
  - `actual_truth/contracts/profile_media_edge_contract.md`: profile/community surfaces share the same media doctrine
- `baseline_interaction`: Still requires new append-only feature entity work and runtime projection expansion.
- `classification`:
  - `canonical_strength`: `MEDIUM`
  - `future_proofing`: `MEDIUM`
  - `implementation_safety`: `MEDIUM`
- `impact_on_aveli_target_model`: Preserves one media doctrine, but hard-codes community as a coequal source domain even though the current canonical source set names only profile media explicitly.
- `risks_if_chosen`: May overstate community as a source domain before that domain is separately declared.
- `risks_if_not_chosen`: The grouped profile/community language in existing doctrine remains less directly represented.

### PCM-DEC-001C

- `decision_id`: `PCM-DEC-001C`
- `decision_topic`: `Exact source entity name or names`
- `proposed_value`: `app.profile_media_placements` plus `app.community_media_placements`
- `alternative_values`:
  - `app.profile_media_placements`
  - `app.profile_community_media_placements`
- `why_this_value`: This option maximizes future specialization by separating profile and community source truth from the start.
- `canonical_support`:
  - `Aveli_System_Decisions.md`: new features must attach via new canonical entities
  - general non-core feature law supports separate entities when semantics differ
- `baseline_interaction`: Requires more append-only schema surface and a larger `runtime_media` expansion than the other options.
- `classification`:
  - `canonical_strength`: `LOW`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `MEDIUM`
- `impact_on_aveli_target_model`: Gives room for future divergence, but introduces more authority surface than the current target model requires.
- `risks_if_chosen`: Risks overfitting community as an independent domain before it is canonically declared.
- `risks_if_not_chosen`: Later refactor may be needed if community-specific truth diverges sharply from profile media.

### PCM-DEC-002A

- `decision_id`: `PCM-DEC-002A`
- `decision_topic`: `Shared vs separate source model`
- `proposed_value`: `Use one profile-media source model; community surfaces consume the same source model through backend read composition`
- `alternative_values`:
  - `Use separate profile and community source models`
- `why_this_value`: The source set explicitly names `profile media` as the feature domain, while existing media doctrine groups `profile/community` at the usage layer. This makes one source model the smallest coherent decision that preserves one media doctrine without introducing a second feature authority.
- `canonical_support`:
  - `Aveli_System_Decisions.md`: `Profile media is a separate feature domain`
  - `actual_truth/contracts/media_unified_authority_contract.md`: profile/community media is a media usage, not a separate resolver system
  - `actual_truth/contracts/profile_media_edge_contract.md`: profile/community surfaces must consume the same chain
- `baseline_interaction`: Minimal append-only expansion path. The same source model can later feed profile and community mounted surfaces without changing the current baseline core.
- `classification`:
  - `canonical_strength`: `HIGH`
  - `future_proofing`: `MEDIUM`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: Best fits the current target model because it keeps profile/community media subordinate to the same unified media law already governing teacher and learner core flows.
- `risks_if_chosen`: If community later becomes an independently governed feature domain, a split may be needed.
- `risks_if_not_chosen`: Choosing separate models now increases schema and task surface before the target model actually requires it.

### PCM-DEC-002B

- `decision_id`: `PCM-DEC-002B`
- `decision_topic`: `Shared vs separate source model`
- `proposed_value`: `Use separate profile and community source models from the start`
- `alternative_values`:
  - `Use one shared profile-media source model`
- `why_this_value`: This option front-loads future specialization and moderation/publication divergence.
- `canonical_support`:
  - general feature-expansion law permits new entities
  - no direct document support prefers this over a shared model today
- `baseline_interaction`: Requires more baseline additions and more runtime projection logic than the shared-model option.
- `classification`:
  - `canonical_strength`: `LOW`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `MEDIUM`
- `impact_on_aveli_target_model`: Could support future social/community divergence, but it is more structure than the currently declared target model needs.
- `risks_if_chosen`: Introduces extra authority complexity without strong present doctrinal support.
- `risks_if_not_chosen`: Later split may become necessary if product direction expands community into its own governed domain.

### PCM-DEC-003A

- `decision_id`: `PCM-DEC-003A`
- `decision_topic`: `Exact authored subject-binding model`
- `proposed_value`: `Use subject_user_id as a soft external user reference in the feature-specific source model, semantically aligned to the same canonical subject identity carried by auth_subjects.user_id, but without making auth_subjects the owner of feature authority`
- `alternative_values`:
  - `Use teacher_user_id and make the feature teacher-only`
  - `Bind feature authority directly to auth_subjects as the owning table`
- `why_this_value`: This preserves the canonical auth-subject identity layer without expanding `auth_subjects` beyond onboarding, role, and admin authority. It also keeps the feature domain open to future non-teacher community consumers if needed.
- `canonical_support`:
  - `AVELI_DATABASE_BASELINE_MANIFEST.md`: `auth_subjects.user_id` is the canonical subject binding above Supabase Auth
  - `AVELI_DATABASE_BASELINE_MANIFEST.md`: `auth_subjects` must not store membership authority or other unrelated authority domains
  - `actual_truth/contracts/onboarding_teacher_rights_contract.md`: `auth_subjects` owns onboarding, role, and admin authority only
  - `Aveli_System_Decisions.md`: external references remain soft references
- `baseline_interaction`: Aligns with the current accepted pattern that `user_id` stays a soft reference without a database foreign key to `auth.users`.
- `classification`:
  - `canonical_strength`: `HIGH`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: Protects teacher approval, editor access, memberships, and learner-content access from being distorted by profile/community media ownership, while still allowing teacher-facing authoring and future user-facing profile/community surfaces.
- `risks_if_chosen`: Requires careful wording so implementers do not treat `auth_subjects` as the feature owner.
- `risks_if_not_chosen`: The contract stays ambiguous about authorship and may accidentally broaden or bypass auth-subject law.

### PCM-DEC-003B

- `decision_id`: `PCM-DEC-003B`
- `decision_topic`: `Exact authored subject-binding model`
- `proposed_value`: `Use teacher_user_id and make profile/community media a teacher-only feature`
- `alternative_values`:
  - `Use subject_user_id`
- `why_this_value`: This is a narrower model that matches the current teacher-centered editor and course-authoring emphasis.
- `canonical_support`:
  - target model includes teacher access, editor flows, uploads, and course selling
  - home-player direct-upload source currently uses `teacher_id`
- `baseline_interaction`: Would align neatly with some current teacher-centered runtime surfaces, but it would hard-code the domain more narrowly than the canonical doctrine currently does.
- `classification`:
  - `canonical_strength`: `MEDIUM`
  - `future_proofing`: `LOW`
  - `implementation_safety`: `MEDIUM`
- `impact_on_aveli_target_model`: Works for current teacher-centric surfaces, but it narrows future community participation more than the current doctrine requires.
- `risks_if_chosen`: Later learner-facing or mixed community surfaces may require rework.
- `risks_if_not_chosen`: Teacher-specific simplicity is reduced.

### PCM-DEC-004A

- `decision_id`: `PCM-DEC-004A`
- `decision_topic`: `Exact publication-state fields and invariants`
- `proposed_value`: `Use one required field visibility with allowed values draft | published; no implicit default; invalid input is rejected explicitly; only published rows may feed runtime_media; visibility never overrides media readiness or access`
- `alternative_values`:
  - `Use visibility plus published_at`
  - `Use active boolean only`
- `why_this_value`: This is the smallest explicit typed publication model that matches the non-core contract expansion rules and existing non-core contract patterns without inventing extra lifecycle state.
- `canonical_support`:
  - `Aveli_System_Decisions.md`: invalid non-core feature input must be rejected explicitly
  - `Aveli_System_Decisions.md`: fallback/default values must not hide missing data
  - `actual_truth/contracts/studio_sessions_edge_contract.md`: explicit typed publication field pattern using `visibility`
  - `actual_truth/contracts/media_unified_authority_contract.md`: runtime truth and frontend representation remain separate
- `baseline_interaction`: This field lives on the new feature-specific source model only. It does not modify existing core tables or override `media_assets.state`.
- `classification`:
  - `canonical_strength`: `HIGH`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: Keeps teacher/editor/profile/community publishing explicit while preserving the current course access and media readiness authorities.
- `risks_if_chosen`: Some future surfaces may later need a richer moderation or archival state model.
- `risks_if_not_chosen`: The contract remains too vague to decide what actually enters runtime truth.

### PCM-DEC-004B

- `decision_id`: `PCM-DEC-004B`
- `decision_topic`: `Exact publication-state fields and invariants`
- `proposed_value`: `Use visibility plus published_at`
- `alternative_values`:
  - `Use visibility only`
- `why_this_value`: Adds explicit publication timing without needing a separate event log contract.
- `canonical_support`:
  - consistent with explicit typed contract design
  - no direct source-set requirement for the timestamp itself
- `baseline_interaction`: Requires one more field and one more invariant than the minimal option.
- `classification`:
  - `canonical_strength`: `MEDIUM`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `MEDIUM`
- `impact_on_aveli_target_model`: Helpful for future auditing and ordering, but not required by the current target model.
- `risks_if_chosen`: Adds more state than is strictly necessary to unblock the contract.
- `risks_if_not_chosen`: Later ordering or audit semantics may need an additional decision.

### PCM-DEC-005A

- `decision_id`: `PCM-DEC-005A`
- `decision_topic`: `Exact profile/community-specific media_purpose value or values`
- `proposed_value`: `Add one new media_purpose value: profile_media`
- `alternative_values`:
  - `profile_community_media`
  - `profile_media` plus `community_media`
- `why_this_value`: `profile media` is the explicitly named feature domain in the canonical source set. One shared profile-media purpose is enough to classify the media usage without fragmenting the unified media domain.
- `canonical_support`:
  - `Aveli_System_Decisions.md`: profile media is the named separate feature domain
  - `actual_truth/contracts/media_unified_authority_contract.md`: profile/community media is a single governed media usage family
  - accepted baseline pattern: distinct purpose values are introduced only when a distinct governed usage requires them
- `baseline_interaction`: Requires one append-only enum expansion above the current accepted values `course_cover`, `lesson_media`, and `home_player_audio`.
- `classification`:
  - `canonical_strength`: `HIGH`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: Preserves one media doctrine and a small stable taxonomy, which is safer for teacher flows, profile/community rendering, and future task generation.
- `risks_if_chosen`: If community later becomes a distinct source domain, a second value may still be needed.
- `risks_if_not_chosen`: The runtime projection path remains ambiguous and implementers may be tempted to reuse the wrong purpose values.

### PCM-DEC-005B

- `decision_id`: `PCM-DEC-005B`
- `decision_topic`: `Exact profile/community-specific media_purpose value or values`
- `proposed_value`: `Add one new media_purpose value: profile_community_media`
- `alternative_values`:
  - `profile_media`
  - `profile_media` plus `community_media`
- `why_this_value`: Mirrors the grouped profile/community language found in existing media doctrine.
- `canonical_support`:
  - `actual_truth/contracts/media_unified_authority_contract.md`
  - `actual_truth/contracts/profile_media_edge_contract.md`
- `baseline_interaction`: Still requires append-only enum expansion and runtime projection work.
- `classification`:
  - `canonical_strength`: `MEDIUM`
  - `future_proofing`: `MEDIUM`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: Keeps a single purpose family, but the name is less consistent with the explicitly named `profile media` feature domain in decisions and manifest.
- `risks_if_chosen`: Bakes community into the purpose taxonomy before community is explicitly declared as a separate source domain.
- `risks_if_not_chosen`: The grouped language in current doctrine is represented less literally.

### PCM-DEC-005C

- `decision_id`: `PCM-DEC-005C`
- `decision_topic`: `Exact profile/community-specific media_purpose value or values`
- `proposed_value`: `Add two values: profile_media and community_media`
- `alternative_values`:
  - `profile_media`
  - `profile_community_media`
- `why_this_value`: Maximizes future distinction between profile and community media categories.
- `canonical_support`:
  - only general feature-expansion law supports this
  - current source set does not explicitly require two purpose values
- `baseline_interaction`: Requires a larger append-only enum expansion and more runtime projection branching.
- `classification`:
  - `canonical_strength`: `LOW`
  - `future_proofing`: `MEDIUM`
  - `implementation_safety`: `MEDIUM`
- `impact_on_aveli_target_model`: Could support future divergence, but adds more taxonomy than the current declared target model needs.
- `risks_if_chosen`: Over-specifies the domain before the current doctrine requires it.
- `risks_if_not_chosen`: If community later becomes fully independent, a later enum addition may be needed.

### PCM-DEC-006A

- `decision_id`: `PCM-DEC-006A`
- `decision_topic`: `Exact append-only baseline or above-baseline authority path that feeds rows into runtime_media`
- `proposed_value`: `Use an append-only accepted baseline path above the current slot range: (1) expand app.media_purpose with profile_media, (2) create app.profile_media_placements as a feature-specific source model above baseline core, (3) extend app.runtime_media to union published profile-media rows, and (4) keep profile/community surfaces dependent on backend read composition only`
- `alternative_values`:
  - `Use a separate above-baseline feature schema outside accepted replayed slots`
  - `Use backend-only transition mapping without runtime_media expansion`
- `why_this_value`: This is the most replayable, deterministic, and canonically aligned path. It follows the same authority pattern already used for lesson media, course cover, and home-player media while keeping non-core feature truth out of core tables.
- `canonical_support`:
  - `Aveli_System_Decisions.md`: new features attach via new canonical entities
  - `Aveli_System_Decisions.md`: no layer may bypass `runtime_media` or backend read composition
  - `AVELI_DATABASE_BASELINE_MANIFEST.md`: baseline does not directly define non-core domains in core tables
  - `backend/supabase/baseline_slots/0017_runtime_media_unified.sql`
  - `backend/supabase/baseline_slots/0018_runtime_media_home_player.sql`
  - `baseline_slots.lock.json`
- `baseline_interaction`: Clean append-only continuation of the accepted baseline. No protected core slot changes are required.
- `classification`:
  - `canonical_strength`: `HIGH`
  - `future_proofing`: `HIGH`
  - `implementation_safety`: `HIGH`
- `impact_on_aveli_target_model`: Best preserves deterministic replay, unified media law, and clean separation from memberships, auth-subject authority, course access, and lesson media while still unblocking future profile/community surfaces.
- `risks_if_chosen`: Requires explicit baseline slots and later task work before runtime can align.
- `risks_if_not_chosen`: Runtime work is likely to drift into non-replayable or non-canonical shortcuts.

### PCM-DEC-006B

- `decision_id`: `PCM-DEC-006B`
- `decision_topic`: `Exact append-only baseline or above-baseline authority path that feeds rows into runtime_media`
- `proposed_value`: `Keep the feature contract outside accepted baseline replay and feed profile/community media through a backend-only transition layer`
- `alternative_values`:
  - `Use append-only accepted baseline slots and runtime_media expansion`
- `why_this_value`: Minimizes database change in the short term.
- `canonical_support`:
  - transition layers are allowed only temporarily and explicitly
  - no direct support makes this the preferred steady-state model
- `baseline_interaction`: Avoids immediate slot additions, but weakens replayability and leaves the runtime truth path under-specified.
- `classification`:
  - `canonical_strength`: `LOW`
  - `future_proofing`: `LOW`
  - `implementation_safety`: `LOW`
- `impact_on_aveli_target_model`: Short-term patchability is improved, but long-term stability and single-path media authority are weakened.
- `risks_if_chosen`: Encourages a temporary path to become de facto truth and risks reintroducing a second media doctrine.
- `risks_if_not_chosen`: Requires committing to the stronger append-only baseline path.
