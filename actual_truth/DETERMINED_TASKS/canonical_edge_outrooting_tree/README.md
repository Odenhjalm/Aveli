# CANONICAL EDGE OUTROOTING TREE

`input(task="Generate deterministic outrooting task tree from completed outrooting audit findings around the stable canonical core", mode="generate")`

## STATUS

READY

This tree is the canonical generate-mode outrooting plan for the remaining edge drift that still surrounds the stable canonical core.

It is derived only from:

- [auth_onboarding_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/auth_onboarding_contract.md)
- [profile_projection_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/profile_projection_contract.md)
- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
- [course_access_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_access_contract.md)
- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
- [home_audio_aggregation_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/home_audio_aggregation_contract.md)
- [referral_membership_grant_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/referral_membership_grant_contract.md)
- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)
- mounted runtime truth re-read from [main.py](/C:/Users/aveli/Aveli/backend/app/main.py)
- baseline truth re-read from [baseline_slots.lock.json](/C:/Users/aveli/Aveli/backend/supabase/baseline_slots.lock.json)
- completed outrooting audit findings already confirmed by direct source inspection

This tree is not speculative.
Each task exists because the completed audit identified a still-mounted drift path, a still-dangerous inactive edge, a stale verification surface, or a contradicted task/document artifact.

## NO-TOUCH CANONICAL CORE

This tree MUST preserve the following surfaces completely untouched:

- `auth.users`
- `app.auth_subjects`
- `app.memberships`
- `app.orders`
- `app.payments`
- `app.course_enrollments`
- canonical course and bundle monetization fields: `teacher_id`, `active_stripe_price_id`, `sellable`
- canonical checkout and webhook completion path

Cross-tree owner tasks consumed here must already exist before execution:

- `AOI-003_baseline_bound_auth_persistence`
- `BCP-042AA_append_home_player_course_link_inclusion_substrate`
- `CMT-001_BASELINE_MEMBERSHIP_FOUNDATION`
- `CMTZ-001_BASELINE_OWNERSHIP_AND_MONETIZATION_FOUNDATION`

This tree consumes those truths.
It does not redefine them.

## AUDIT METHOD

The completed outrooting audit used semantic retrieval fallback plus direct source inspection.
No approved local semantic index artifact was available during the audit, so no rebuild was attempted and no index artifact was mutated.

This generate pass re-read only the current authoritative inputs needed to materialize deterministic tasks:

- current contracts
- current mounted runtime truth
- current baseline truth
- the completed audit findings

## VERIFIED AUDIT IDS

- `OEA-01` the canonical core is stable and must remain untouched: `auth.users`, `app.auth_subjects`, `app.memberships`, `app.orders`, `app.payments`, `app.course_enrollments`, canonical course and bundle monetization fields, and canonical checkout plus webhook completion
- `OEA-02` mounted studio home-audio course-link ownership still resolves through `backend/app/repositories/home_audio_sources.py` using `c.created_by AS teacher_id`, and mounted `backend/app/routes/studio.py` consumes that path
- `OEA-03` mounted studio quiz ownership still resolves through `backend/app/models.py` using `c.created_by`, and mounted `backend/app/routes/studio.py` consumes that path
- `OEA-04` mounted `backend/app/routes/api_events.py` uses canonical membership access but still carries legacy owner checks and visibility branches keyed off `created_by`
- `OEA-05` `backend/app/routes/auth.py` still emits `role` and `is_admin` claims even though backend current-user authority is read canonically from `app.auth_subjects`
- `OEA-06` inactive AI and seminar edges still read `app.enrollments` from `backend/app/services/tool_dispatcher.py` and `backend/app/repositories/seminars.py`
- `OEA-07` stale tests still target unmounted routes and legacy drift surfaces, while guard tests already exist for upload-route retirement, commerce entrypoint boundaries, auth-subject authority, and notification audience separation
- `OEA-08` current contract and task artifacts still contain implementation-drift claims contradicted by mounted runtime truth and guard tests
- `OEA-09` active support surfaces still use schema introspection in `backend/app/repositories/media_assets.py` and tolerant schema probing in `backend/app/services/domain_observability/user_inspection.py`
- `OEA-10` a stale Stripe Connect support branch still survives in `backend/app/services/stripe_webhook_support_service.py` while mounted webhook runtime ignores `account.*`
- `OEA-11` dormant sessions edges still retain `stripe_price_id` and related route or schema residue
- `OEA-12` alias-normalization and legacy upload or media helper residue still survives in inactive or support-only surfaces

## TASK CATEGORIES

- `ACTIVE AUTHORITY DRIFT`
- `ACTIVE AUXILIARY DRIFT`
- `SHADOW AUTHORITY CLEANUP`
- `INACTIVE / DEAD-CODE QUARANTINE`
- `TEST ALIGNMENT`
- `DOC / TASK ALIGNMENT`
- `AGGREGATE`

## REQUIRED CLEANUP LANE

These tasks are required before future core feature work may safely proceed:

1. [OET-001_STUDIO_HOME_AUDIO_OWNERSHIP_CLEANUP.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-001_STUDIO_HOME_AUDIO_OWNERSHIP_CLEANUP.md)
2. [OET-002_STUDIO_QUIZ_OWNERSHIP_CLEANUP.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-002_STUDIO_QUIZ_OWNERSHIP_CLEANUP.md)
3. [OET-003_EVENTS_OWNERSHIP_CLEANUP.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-003_EVENTS_OWNERSHIP_CLEANUP.md)
4. [OET-004_JWT_SHADOW_CLAIM_CLEANUP.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-004_JWT_SHADOW_CLAIM_CLEANUP.md)
5. [OET-006_TEST_DRIFT_ALIGNMENT.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-006_TEST_DRIFT_ALIGNMENT.md)
6. [OET-007_DOC_TASK_DRIFT_ALIGNMENT.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-007_DOC_TASK_DRIFT_ALIGNMENT.md)
7. [OET-011_REQUIRED_OUTROOTING_GATE.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-011_REQUIRED_OUTROOTING_GATE.md)

## OPTIONAL LATER HARDENING

These tasks are evidence-backed but may be deferred until the required cleanup lane is complete:

1. [OET-005_UNMOUNTED_ENROLLMENTS_QUARANTINE.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-005_UNMOUNTED_ENROLLMENTS_QUARANTINE.md)
2. [OET-008_RUNTIME_SUPPORT_INTROSPECTION_HARDENING.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-008_RUNTIME_SUPPORT_INTROSPECTION_HARDENING.md)
3. [OET-009_STALE_WEBHOOK_AND_ROUTE_QUARANTINE.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-009_STALE_WEBHOOK_AND_ROUTE_QUARANTINE.md)
4. [OET-010_SESSIONS_ALIAS_AND_LEGACY_FIELD_QUARANTINE.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-010_SESSIONS_ALIAS_AND_LEGACY_FIELD_QUARANTINE.md)
5. [OET-012_OPTIONAL_HARDENING_GATE.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-012_OPTIONAL_HARDENING_GATE.md)

## DAG ENTRYPOINT

Within this tree, the first outrooting task remains [OET-001_STUDIO_HOME_AUDIO_OWNERSHIP_CLEANUP.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-001_STUDIO_HOME_AUDIO_OWNERSHIP_CLEANUP.md).

It is mounted runtime, it is the narrowest remaining `created_by` authority surface adjacent to the canonical course core, and it is legal only after cross-tree prerequisites are satisfied.
It now depends on explicit baseline ownership for `app.home_player_course_links` plus already-ratified course ownership truth from `CMTZ-001` rather than reopening any core decision.

Execution order and dependency graph are defined in:

- [DAG_SUMMARY.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/DAG_SUMMARY.md)

Machine-readable task metadata is defined in:

- [task_manifest.json](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/task_manifest.json)
