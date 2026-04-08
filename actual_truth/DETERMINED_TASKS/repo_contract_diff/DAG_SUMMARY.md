# Repo Contract Diff DAG Summary

## Final State

- STATUS: `TASKS_READY`

## Task IDs

- `RCD-001_RUNTIME_ROUTE_AUTHORITY_SYNC`
- `RCD-002_MEDIA_WRITE_AUTHORITY_DECISION`
- `RCD-003_ONBOARDING_ROLE_BASELINE_SCHEMA_ALIGNMENT`
- `RCD-004_ONBOARDING_MUTATION_SURFACE_ALIGNMENT`
- `RCD-005_ROLE_TEACHER_RIGHTS_RUNTIME_ALIGNMENT`
- `RCD-006_MEDIA_WRITE_ROUTE_ALIGNMENT`
- `RCD-007_MEDIA_READ_COMPOSITION_ALIGNMENT`
- `RCD-008_LEGACY_SURFACE_ISOLATION_SWEEP`
- `RCD-009_MIRROR_REFRESH_AFTER_PRIMARY_ALIGNMENT`

## Dependency Graph In Topological Order

1. `RCD-001_RUNTIME_ROUTE_AUTHORITY_SYNC`
2. `RCD-003_ONBOARDING_ROLE_BASELINE_SCHEMA_ALIGNMENT`
3. `RCD-002_MEDIA_WRITE_AUTHORITY_DECISION`
4. `RCD-004_ONBOARDING_MUTATION_SURFACE_ALIGNMENT`
5. `RCD-005_ROLE_TEACHER_RIGHTS_RUNTIME_ALIGNMENT`
6. `RCD-006_MEDIA_WRITE_ROUTE_ALIGNMENT`
7. `RCD-007_MEDIA_READ_COMPOSITION_ALIGNMENT`
8. `RCD-008_LEGACY_SURFACE_ISOLATION_SWEEP`
9. `RCD-009_MIRROR_REFRESH_AFTER_PRIMARY_ALIGNMENT`

## Smallest Safe Execution Entrypoint

- `RCD-001_RUNTIME_ROUTE_AUTHORITY_SYNC`
- Rationale: subsequent runtime and media tasks depend on a correct statement of what is actually mounted and active.

## Highest-Risk Tasks

- `RCD-003_ONBOARDING_ROLE_BASELINE_SCHEMA_ALIGNMENT`
  - Protected baseline slots and lockfile must change together without reintroducing legacy auth semantics.
- `RCD-005_ROLE_TEACHER_RIGHTS_RUNTIME_ALIGNMENT`
  - Permission semantics currently span admin override, role fields, and supporting tables.
- `RCD-007_MEDIA_READ_COMPOSITION_ALIGNMENT`
  - Existing cover and studio read paths still mix canonical composition with direct storage-derived payload behavior.

## Doc-Only Tasks vs Code Tasks

- Doc-only:
  - `RCD-001_RUNTIME_ROUTE_AUTHORITY_SYNC`
  - `RCD-002_MEDIA_WRITE_AUTHORITY_DECISION`
  - `RCD-009_MIRROR_REFRESH_AFTER_PRIMARY_ALIGNMENT`
- Code tasks:
  - `RCD-003_ONBOARDING_ROLE_BASELINE_SCHEMA_ALIGNMENT`
  - `RCD-004_ONBOARDING_MUTATION_SURFACE_ALIGNMENT`
  - `RCD-005_ROLE_TEACHER_RIGHTS_RUNTIME_ALIGNMENT`
  - `RCD-006_MEDIA_WRITE_ROUTE_ALIGNMENT`
  - `RCD-007_MEDIA_READ_COMPOSITION_ALIGNMENT`
  - `RCD-008_LEGACY_SURFACE_ISOLATION_SWEEP`

## Domain Partitioning

- Authority-doc updates:
  - `RCD-001_RUNTIME_ROUTE_AUTHORITY_SYNC`
  - `RCD-002_MEDIA_WRITE_AUTHORITY_DECISION`
- Runtime route alignment:
  - `RCD-006_MEDIA_WRITE_ROUTE_ALIGNMENT`
- Mutation-surface alignment:
  - `RCD-004_ONBOARDING_MUTATION_SURFACE_ALIGNMENT`
  - `RCD-005_ROLE_TEACHER_RIGHTS_RUNTIME_ALIGNMENT`
- Baseline / bootstrap alignment:
  - `RCD-003_ONBOARDING_ROLE_BASELINE_SCHEMA_ALIGNMENT`
- Legacy surface removal or isolation:
  - `RCD-008_LEGACY_SURFACE_ISOLATION_SWEEP`
- Mirror refresh:
  - `RCD-009_MIRROR_REFRESH_AFTER_PRIMARY_ALIGNMENT`

## Audit Notes That Drive The DAG

- Mounted runtime truth in `backend/app/main.py` no longer matches `actual_truth/system_runtime_rules.md`.
- Canonical onboarding and teacher-rights contract does not match baseline profile enums/defaults or mounted runtime state derivation.
- Teacher-rights evaluation in mounted runtime still treats admin and supporting tables as teacher authority.
- Canonical lesson-media write authority is not yet explicitly decided in primary contract documentation.
- Canonical media read composition is still mixed with legacy preview fields and direct storage-derived cover URLs.
- Repo-local semantic retrieval tooling exists under `tools/index/`, but `.repo_index/` is not bootstrapped in the current workspace, so retrieval tooling is supporting infrastructure rather than current authority.
