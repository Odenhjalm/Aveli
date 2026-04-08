# AUTH_ONBOARDING_CONTRACT_ALIGNMENT TASK TREE

## SECTION: TASK TREE

### 1. CANONICAL_ENTRYPOINT_REPLACEMENT

- `AOC-001` -> replace mounted Auth + Onboarding entrypoints with the canonical contract inventory

### 2. DUPLICATE_SURFACE_COLLAPSE

- `AOC-002` -> collapse duplicate auth/profile route and schema surfaces into one canonical implementation surface

### 3. LEGACY_SURFACE_ISOLATION

- `AOC-003` -> isolate legacy shadow route modules and direct imports from validation flow before removal

### 4. SUBJECT_PROFILE_AUTHORITY_REPLACEMENT

- `AOC-004` -> replace profile-authority leakage so only `app.auth_subjects` owns onboarding and role authority

### 5. LEGACY_ROLE_AND_STATE_REMOVAL

- `AOC-005` -> remove invalid teacher inference, legacy onboarding-state, and cross-domain auth fields while preserving canonical role compatibility fallback

### 6. AUTH_TEXT_LANGUAGE_REPLACEMENT

- `AOC-006` -> replace remaining non-Swedish Auth + Onboarding user-facing text on canonical surfaces

### 7. VALIDATION_GATE_REWRITE

- `AOC-007` -> rewrite tests, fixtures, and scripts so validation uses canonical Auth + Onboarding truth only

### 8. AGGREGATE_VERIFICATION

- `AOC-008` -> aggregate grep and route-inventory verification for the full Auth + Onboarding contract surface

## DEPENDENCY SUMMARY

- Root: `AOC-001`
- Primary spine: `AOC-001 -> AOC-002 -> AOC-003`
- Authority rewrite branch: `AOC-002 -> AOC-004`
- Legacy removal branch: `AOC-003 + AOC-004 -> AOC-005 -> AOC-006`
- Validation gate: `AOC-001 + AOC-003 + AOC-004 + AOC-005 + AOC-006 -> AOC-007`
- Aggregate closeout: `AOC-007 -> AOC-008`
- No task may skip `AOC-003` if `api_auth.py` or `api_profiles.py` still appears in active validation imports.
- No task may skip `AOC-004` if any write path still persists onboarding or role authority through `app.profiles`.

## MATERIALIZED TASK FILES

- `AOC-001_canonical_entrypoint_replacement.md`
- `AOC-002_auth_surface_collapse.md`
- `AOC-003_legacy_surface_isolation.md`
- `AOC-004_subject_profile_authority_replacement.md`
- `AOC-005_role_and_onboarding_legacy_removal.md`
- `AOC-006_auth_text_language_replacement.md`
- `AOC-007_auth_onboarding_gate_rewrite.md`
- `AOC-008_auth_onboarding_aggregate_gate.md`
- `task_manifest.json`
