# DEPLOYMENT GUARDRAIL POLICY

## STATUS

ACTIVE

This policy defines the fail-closed deployment guardrails for safe Aveli feature
rollout and Baseline V2 slot additions.

This policy operates under:

- `actual_truth/contracts/production_deployment_contract.md`
- `actual_truth/contracts/baseline_v2_release_cutover_contract.md`
- `actual_truth/contracts/baseline_v2_authority_freeze_contract.md`
- `actual_truth/contracts/SYSTEM_LAWS.md`
- `actual_truth/contracts/supabase_integration_boundary_contract.md`
- `actual_truth/contracts/auth_onboarding_contract.md`
- `actual_truth/contracts/onboarding_entry_authority_contract.md`
- `actual_truth/contracts/profile_projection_contract.md`
- `actual_truth/contracts/profile_community_media_contract.md`
- `actual_truth/contracts/commerce_membership_contract.md`
- `actual_truth/contracts/course_access_contract.md`
- `actual_truth/contracts/course_monetization_contract.md`
- `actual_truth/contracts/storage_lifecycle_contract.md`
- `actual_truth/contracts/referral_membership_grant_contract.md`
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- `backend/supabase/baseline_v2_slots.lock.json`

This policy is deployment authority only. It does not authorize production
mutation by itself.

## 1. Audited Inputs

The deployment audit for this policy accounted for the following task-requested
inputs and their current authoritative equivalents:

- `actual_truth/contracts/auth_onboarding_contract.md`
- `actual_truth/contracts/profile_projection_contract.md`
- `actual_truth/contracts/course_monetization_contract.md`
- `actual_truth/contracts/SYSTEM_LAWS.md`
- `backend/supabase/baseline_slots.lock.json` (`ARCHIVED_LEGACY_NON_AUTHORITATIVE` input only)
- `backend/supabase/baseline_v2_slots.lock.json`

The task-requested `baseline_slots_strategy.md` does not exist in this
repository.

The current authoritative replacements for slot strategy are:

- `actual_truth/contracts/baseline_v2_authority_freeze_contract.md`
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`
- `backend/supabase/baseline_v2_slots.lock.json`
- `backend/supabase/baseline_slots/README.md` (archived legacy and non-authoritative reference only)

The current production deployment strategy was also audited through:

- `fly.toml`
- `netlify.toml`
- `README.md`
- `.github/workflows/deploy.yml`
- `.github/workflows/release-manual.yml`
- `.github/workflows/backend-ci.yml`
- `.github/workflows/flutter.yml`
- `backend/bootstrap/baseline_v2.py`
- `backend/bootstrap/run_server.py`
- `backend/bootstrap/run_worker.py`
- `backend/scripts/replay_v2.sh`
- `backend/scripts/apply_supabase_migrations.sh`
- `backend/scripts/db_verify_remote_readonly.sh`
- `backend/scripts/supabase_verify_env.py`
- `ops/check_baseline_slots.py`
- `ops/prod_readonly_smoke.sh`

## 2. Current Canonical Deployment Model

- Backend production authority is Fly app `aveli` with `APP_ENV=production`.
- Fly production must keep separate `app` and `worker` process groups.
- Production app health requires `GET /healthz` and `GET /readyz`.
- Frontend production authority is a Netlify source build from `main`.
- Netlify branch deploys are previews only and are not production authority.
- Production backend target for web is `https://aveli.fly.dev`.
- Production database authority is the deployed runtime target, not repo-local
  `.vscode/`, `.temp/`, local env files, or operator notes.
- Canonical database baseline authority is
  `backend/supabase/baseline_v2_slots/` plus
  `backend/supabase/baseline_v2_slots.lock.json`.
- Hosted Supabase owns physical `auth` and `storage` schema.
- Production replay must verify provider substrate interfaces and must not
  recreate `auth` or `storage`.
- Runtime startup and worker startup verify Baseline V2 and fail closed.
- Runtime startup will not auto-replay an empty schema.
- Fly `release_command` is the canonical execute-mode production slot cutover
  path for bounded Baseline V2 slot deltas.

## 3. Canonical State Dependencies Protected By This Policy

The following state is deployment-critical and must be preserved across any
rollout:

- `auth.users` as external identity and email-verification substrate only
- `app.auth_subjects` as canonical onboarding, role, and admin subject truth
- `app.profiles` as projection-only profile persistence
- `app.profile_media_placements` as profile/community authored-placement truth
- `app.memberships` as the single current membership authority row per user
- `app.orders` and `app.payments` as purchase and settlement trail
- `app.course_enrollments` as protected course-access authority
- `app.referral_codes` as referral identity and redemption authority
- `app.media_assets` as media identity and lifecycle truth
- `app.runtime_media` as read-only projection only
- `app.home_player_course_links` as canonical course-linked home-audio source
  truth
- `storage.buckets` and `storage.objects` as physical persistence only

Deployment interpretation rules:

- `app.profiles` must never be used as onboarding, routing, membership, or
  media source truth.
- `app.memberships` must never be rebuilt, aggregated, or inferred from Stripe
  state during deployment.
- `storage.objects` and `storage.buckets` must never become rollout authority,
  fallback truth, or repair truth.
- `app.runtime_media` must never be written directly during rollout.
- Storage object existence must never be used to infer canonical media truth
  without the governing `app.media_assets` and placement source rows.

## 4. Slot Chain And Replay Facts

Current Baseline V2 lock facts:

- Canonical slot chain is `V2_0001` through the final slot recorded in
  `backend/supabase/baseline_v2_slots.lock.json`.
- Current highest accepted slot is the final slot entry in the canonical V2
  lock.
- Lock-protected replay order is strictly ascending and gap-free.
- `protected_min_slot = 1`.
- `protected_max_slot = 16`.
- Slots `0001` through `0016` are immutable protected history.
- Slots above `0016` are accepted append-only continuation and remain lock
  protected once accepted.
- Legacy `backend/supabase/baseline_slots/` and `backend/supabase/baseline_slots.lock.json` are `ARCHIVED_LEGACY_NON_AUTHORITATIVE`.

Replay facts:

- `backend/scripts/replay_v2.sh` is the canonical replay entrypoint.
- `local_dev` replay provisions locked local substrate and replays app-owned
  slots.
- `hosted_supabase` replay is allowed only with explicit
  `ALLOW_HOSTED_BASELINE_REPLAY=1`.
- Hosted destructive replay is forbidden for protected hosted environments and
  production.
- Production runtime verification reads the current schema and fails if it does
  not match the V2 lock.

## 5. Repo-Visible Drift And Operational Gaps

The audit found the following deployment-relevant gaps:

- `.github/workflows/release-manual.yml` still instructs operators to run
  a manual migration step instead of relying on the canonical release-machine
  cutover path carried by the release artifact.
- `.github/workflows/backend-ci.yml` and `.github/workflows/flutter.yml` still
  seed CI databases through `backend/scripts/apply_supabase_migrations.sh`.
- `.github/workflows/flutter.yml` starts backend smoke tests with direct
  `uvicorn app.main:app`, not the canonical `backend.bootstrap.run_server`
  bootstrap path.
- `README.md` still contains a legacy deployment note referencing baseline
  scope through `0038`, which is not the current V2 slot chain.
- The repository does not define a first-class production-like staging
  environment for Baseline V2 hosted replay.
- Netlify previews verify frontend build behavior only. They are not database
  staging, backend staging, or worker staging.
- `backend/scripts/db_verify_remote_readonly.sh` and
  `backend/scripts/supabase_verify_env.py` are useful read-only checks, but
  they do not replace V2 schema-hash verification.

Blocking interpretation:

- The repository now contains a canonical non-destructive production slot
  applier for accepted V2 slot additions:
  `backend.bootstrap.baseline_v2_cutover`, executed only through Fly
  `release_command`.
- The bounded execute-mode authority for the current release lives in
  `backend/supabase/baseline_v2_production_cutover.json`.
- `backend/scripts/replay_v2.sh` is replay authority, not production mutation
  authority for stateful business environments.
- `backend/scripts/apply_supabase_migrations.sh` is legacy migration tooling and
  must not be used as production slot authority.
- Therefore any production rollout that requires DB mutation for a new V2 slot
  is allowed only when the exact release artifact carries an approved bounded
  cutover plan for the exact slot delta.

## 6. Non-Negotiable Deployment Guardrails

- No hard reset, destructive replay, or app-schema rebuild is allowed on
  production.
- No production deploy may use archived legacy baseline slots or legacy
  migration chains as authority.
- No accepted V2 slot may be edited in place.
- Every new slot must be append-only, strictly sequenced, and lock-added in the
  same change.
- No production write is allowed before pre-deploy audit and verification are
  complete.
- No production rollout may proceed if the exact Supabase project target is not
  runtime-verified.
- No production rollout may proceed if affected canonical accounts have not been
  identified and scoped for verification.
- No rollout may use `app.profiles`, `app.runtime_media`, Stripe runtime state,
  or storage URLs as fallback authority.
- No rollout may treat `auth` or `storage` substrate verification as permission
  to mutate provider-owned schemas.
- Production rollback by hard reset is forbidden.
- Production recovery must be forward-fix, traffic rollback, or feature disable
  without rewriting canonical business state.

## 7. Required Verification Scope For Affected Accounts

Every rollout must declare the exact affected account cohort before any
production write or deploy.

The verification set must include every directly affected user, teacher, or
course entity that could be touched by the change, plus all linked canonical
rows and storage objects in scope.

For each affected account, verify the applicable canonical surfaces:

- `app.auth_subjects.user_id`, `email`, `role`, `onboarding_state`
- `app.profiles.display_name`, `bio`, `avatar_media_id`
- `app.profile_media_placements.subject_user_id`, `media_asset_id`, `visibility`
- `app.memberships.user_id`, `status`, `source`, `effective_at`, `expires_at`
- `app.orders` and `app.payments` for any commerce-touching rollout
- `app.course_enrollments.source`, `granted_at`, `current_unlock_position`
- `app.referral_codes` active and redemption state for referral-touching rollout
- `app.media_assets.purpose`, `media_type`, `state`, `playback_format`,
  `playback_object_path`
- `app.runtime_media` projection presence or absence, but only as projection
  evidence
- `storage.objects` existence for the exact referenced original/playback object
  coordinates where media/storage is in scope

Fail-closed rule:

- If the affected account list is unknown, incomplete, or inferred from
  non-canonical sources, STOP.

## 8. Procedure For Baseline Slot Additions

### 8.1 Pre-Change Audit

1. Identify the exact authority change.
2. Confirm the change is app-owned schema only.
3. Confirm the change does not require provider-owned `auth` or `storage`
   mutation.
4. Map every affected authority:
   `runtime surface -> canonical table/view/function -> contract owner`.
5. Record the affected account cohort and affected storage objects.
6. Confirm that no existing accepted slot needs in-place editing.

If any authority mapping is ambiguous:

- STOP

### 8.2 Slot Authoring Guardrail

1. Assign the next slot number strictly above the current highest accepted
   slot.
2. Add exactly one new V2 slot file under
   `backend/supabase/baseline_v2_slots/`.
3. Update `backend/supabase/baseline_v2_slots.lock.json` in the same change.
4. Update contracts and baseline manifest in the same change when authority
   classification changes.
5. Run `ops/check_baseline_slots.py`.

Forbidden:

- renumbering accepted slots
- replacing accepted slot files
- editing protected history
- adding slots to the archived legacy baseline directory
- using `backend/supabase/migrations/` or `supabase/migrations/` as slot
  authority

### 8.3 Local Clean Replay

1. Use the canonical local profile only.
2. Run clean replay from an empty local app-owned schema through
   `backend/scripts/replay_v2.sh`.
3. Require the V2 lock to verify before replay.
4. Require schema-hash, counts, triggers, functions, and substrate interface to
   match the lock after replay.
5. Start backend through `backend.bootstrap.run_server`.
6. Verify `/healthz` and `/readyz`.
7. Start worker through the canonical worker bootstrap when the change touches
   worker-owned domains.
8. Verify the affected account invariants against the replayed local database.

If replay, schema verification, backend readiness, or worker readiness fails:

- STOP

### 8.4 Hosted Staging Replay

Hosted replay is optional and restricted.

Allowed hosted replay target:

- an explicitly isolated hosted Supabase target
- classified as `BASELINE_RESET_CLASS=stateless_verification`
- empty or explicitly disposable app-owned schema state
- not production
- not any stateful business environment

Required hosted replay rules:

- `ALLOW_HOSTED_BASELINE_REPLAY=1`
- verify provider-owned `auth` and `storage` interface only
- replay app-owned slots only
- no business-state preservation claims
- no use of production credentials

If no such staging target exists:

- do not improvise one
- do not replay against production
- continue with local clean replay plus production read-only preflight only

### 8.5 Production Promotion Gate For Slot Changes

Before any production slot-related mutation is approved:

1. Prove the new slot is append-only and lock-recorded.
2. Prove local clean replay success on the exact release SHA.
3. Prove exact production Supabase target identity through runtime-derived
   evidence.
4. Run production read-only environment verification.
5. Run production read-only DB verification.
6. Capture pre-deploy snapshots for all affected canonical accounts.
7. Confirm the release-machine cutover contract and bounded cutover plan exist
   for the exact slot delta.

If step 7 is missing:

- STOP
- production slot mutation is blocked

### 8.6 Execute-Mode Production Slot Promotion

The only accepted execute-mode production slot promotion path is:

1. Build the exact release artifact that carries the new lock and cutover plan.
2. Run `fly deploy` for that exact release artifact.
3. Let Fly execute `release_command` in a temporary release Machine.
4. Require `backend.bootstrap.baseline_v2_cutover` to:
   - verify the lock
   - verify the bounded cutover plan
   - verify runtime DB target safety
   - require the DB to be already at the target state or at the exact bounded
     predecessor state
   - apply only the listed slot files in strict order
   - verify post-step schema hash and counts
   - verify the final state through `verify_v2_runtime()`
5. Allow app/worker Machine replacement only if the release command exits zero.

If any step fails:

- STOP
- do not replace app or worker Machines

## 9. Procedure For Non-Schema Feature Rollout

If the rollout does not require a new V2 slot:

1. Perform the authority and affected-account audit.
2. Confirm the release SHA is on `origin/main`.
3. Confirm the worktree is clean for the release operator.
4. Verify exact production Supabase target.
5. Run read-only production env and DB verification.
6. Capture pre-deploy account snapshots for all affected accounts.
7. Deploy backend and worker for that exact SHA when backend behavior changes.
8. Trigger Netlify production source build for that exact SHA only when frontend
   behavior changes.
9. Run post-deploy read-only audit.

## 10. Production Pre-Deploy Checklist

All production rollouts must pass the following before any write or deploy:

- release SHA is exact and on `origin/main`
- required GitHub checks are green
- production Fly app is `aveli`
- production app and worker process groups are separate
- exact production Supabase target is runtime-verified
- no stale or conflicting project refs are visible across runtime authority
  surfaces
- affected account cohort is recorded
- pre-deploy account snapshots are captured
- storage substrate interface expectations are checked for affected media
  objects
- no legacy migration or legacy baseline path is in the rollout plan
- no destructive replay or reset command is in the rollout plan

## 11. Production Rollout Order

When production rollout is allowed:

1. Complete the read-only preflight and snapshot steps first.
2. If the release carries a V2 slot delta, deploy the exact release artifact so
   Fly can execute the canonical release-machine cutover before Machine
   replacement.
3. If no DB mutation is required, deploy backend Fly app for the exact release
   SHA directly.
4. Verify `GET /healthz` and `GET /readyz`.
5. Verify worker process group separately for launch-required worker domains.
6. Trigger Netlify production source build for the same SHA, if needed.
7. Do not publish frontend production against an unverified backend/DB target.

## 12. Post-Deployment Audit

The post-deployment audit is mandatory and read-only.

Required checks:

- `GET /healthz`
- `GET /readyz`
- read-only smoke against production HTTP surfaces
- affected-account canonical state verification against pre-deploy snapshots
- membership integrity verification for every affected user
- onboarding-state verification for every affected user
- profile/avatar projection verification for every affected user in scope
- referral redemption and source verification for every affected referral in
  scope
- media/storage verification for every affected governed media object in scope

Post-deploy expectations:

- no unexpected change to `app.auth_subjects`
- no unexpected change to `app.memberships`
- no unexpected change to `app.profiles`
- no unexpected change to `app.referral_codes`
- no unexpected change to `app.course_enrollments`
- no unexpected projection drift in `app.runtime_media`
- no storage-driven authority drift

If any post-deploy audit step fails:

- classify the failure
- stop further rollout
- do not hard reset production
- recover by forward-fix or traffic rollback only

## 13. Explicit Fail-Closed Conditions

Deployment must stop immediately if any of the following is true:

- production target Supabase project is not exact
- rollout plan references legacy migrations as authority
- rollout plan requires destructive replay on hosted stateful data
- accepted slot chain would be edited in place
- affected account scope is missing
- canonical state verification queries are missing
- provider-owned `auth` or `storage` schema mutation is required
- `app.profiles`, `app.runtime_media`, Stripe state, or storage URLs are used as
  fallback authority
- post-deploy audit plan is missing
- the exact production DB promotion method for a new slot delta is undefined
- the release artifact lacks the bounded cutover plan required for its slot delta

## 14. Final Assertion

- Production hard reset is forbidden.
- Baseline slot evolution is append-only and strictly sequenced.
- No production write occurs before audit and verification.
- Canonical state for all affected accounts must be verified before and after
  rollout.
- Hosted replay is scoped to local verification or explicit stateless staging
  only.
- Production deploy and post-deploy audit must fail closed on any ambiguity.
- Baseline V2 slot additions may reach production only through the canonical
  release-machine cutover path for the exact slot delta.
