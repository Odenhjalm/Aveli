# RCD-009_MIRROR_REFRESH_AFTER_PRIMARY_ALIGNMENT

- TYPE: `mirror-refresh`
- TITLE: `Refresh downstream mirrors after primary contract and runtime alignment`
- DOMAIN: `mirror refresh`

## Problem Statement

Primary authority and runtime-alignment work will leave downstream mirrors stale until they are refreshed. Mirror refresh must happen only after the primary docs and repo enforcement surfaces are aligned.

## Primary Authority Reference

- `Aveli_System_Decisions.md`
- `aveli_system_manifest.json`
- `actual_truth/contracts/onboarding_teacher_rights_contract.md`
- `actual_truth/contracts/media_unified_authority_contract.md`
- `actual_truth/contracts/lesson_media_edge_contract.md`
- `actual_truth/system_runtime_rules.md`

## Implementation Surfaces Affected

- `actual_truth/rule_layers/OS.md`
- `actual_truth/rule_layers/DECISIONS.md`
- `actual_truth/rule_layers/MANIFEST.md`
- `actual_truth/rule_layers/CONTRACT.md`

## DEPENDS_ON

- `RCD-001_RUNTIME_ROUTE_AUTHORITY_SYNC`
- `RCD-002_MEDIA_WRITE_AUTHORITY_DECISION`
- `RCD-004_ONBOARDING_MUTATION_SURFACE_ALIGNMENT`
- `RCD-005_ROLE_TEACHER_RIGHTS_RUNTIME_ALIGNMENT`
- `RCD-006_MEDIA_WRITE_ROUTE_ALIGNMENT`
- `RCD-007_MEDIA_READ_COMPOSITION_ALIGNMENT`
- `RCD-008_LEGACY_SURFACE_ISOLATION_SWEEP`

## Acceptance Criteria

- Downstream mirrors restate the current primary truth without introducing new authority.
- Mirror content does not contradict primary contracts or runtime-route authority.
- Mirror refresh occurs after, not before, primary alignment.

## Stop Conditions

- Stop if any primary authority file remains unresolved or contradictory at refresh time.
- Stop if mirror generation would silently preserve removed legacy authority.

## Out Of Scope

- New business rules
- Historical audit snapshots
- Runtime behavior changes
