# PRODUCTION DEPLOYMENT CONTRACT

## STATUS

ACTIVE

This contract defines the canonical production deployment authority for Aveli.
It operates under `baseline_v2_authority_freeze_contract.md`,
`baseline_v2_release_cutover_contract.md`, `SYSTEM_LAWS.md`,
`supabase_integration_boundary_contract.md`, `auth_onboarding_contract.md`,
`commerce_membership_contract.md`, `course_access_contract.md`,
`course_public_surface_contract.md`, `media_unified_authority_contract.md`,
`home_audio_aggregation_contract.md`, `profile_community_media_contract.md`,
`media_pipeline_contract.md`, and `livekit_runtime_contract.md`.

This contract owns production deployment authority only. It does not redefine
Supabase substrate law, baseline schema law, auth/onboarding law, commerce law,
course-access law, or media law.

## 1. CONTRACT LAW

- The authoritative Fly production app is `aveli`.
- Production runtime means the Fly app `aveli` with `APP_ENV=production`.
- Production runtime database selection is owned by backend runtime environment,
  not by local developer defaults, legacy migration state, or ad hoc scripts.
- Production deployment planning is invalid while this contract conflicts with
  `actual_truth/contracts/baseline_v2_authority_freeze_contract.md`.
- Production launch is blocked unless the canonical Baseline V2 slot chain has
  been applied to the intended production Supabase database target and verified
  against the contract set.
- Production launch is blocked unless backend runtime, worker runtime, public
  courses, auth/onboarding, membership, course access, media, and payment
  surfaces pass their launch gates.
- Production launch is blocked if production database credentials, project
  targeting, or old connection strings are exposed, stale, ambiguous, or
  mismatched.
- Production launch must fail closed. No local database, legacy migration path,
  stale Supabase project, or fallback credential may become production runtime
  authority.

## 2. PRODUCTION DEPLOYMENT AUTHORITY

Canonical Fly production authority:

- Fly app identity: `aveli`
- Fly primary region: `arn`
- Fly production environment marker: `APP_ENV=production`
- HTTP service process group: `app`
- Worker process group: `worker`

Process groups:

- `app` owns HTTP/API runtime only.
- `worker` owns worker runtime only.
- `http_service.processes` must remain scoped to `app`.
- `worker` must not be exposed as the HTTP service process group.

Health and readiness expectations:

- Fly HTTP health check must target the `app` process group.
- The minimum Fly HTTP health path is `GET /healthz`.
- Public launch also requires `GET /readyz` to pass against the deployed
  production app, because `/healthz` proves only process responsiveness while
  `/readyz` proves database readiness.

## 3. APP AND WORKER SEPARATION

- The app process must not launch local background workers in cloud runtime.
- In cloud runtime, app startup must skip local background workers.
- The worker process group must be launched and verified separately.
- Worker verification must prove that worker-owned MVP domains required by
  launch are healthy against the same production database authority as the app
  process.
- Non-MVP worker domains must not block MVP public launch unless an active
  canonical contract explicitly promotes that worker domain into launch scope.
- Worker authority remains subordinate to the existing domain contracts:
  - media processing authority remains under `media_pipeline_contract.md`
  - drip progression remains worker-owned under `Aveli_System_Decisions.md`
  - membership expiry warning behavior must not redefine membership authority

## 4. PRODUCTION DATABASE AUTHORITY

The production database target must be the intended Supabase project for Aveli
production.

Current repo-targeting evidence is not clean enough to declare a verified
production target:

- `backend/supabase/.temp/project-ref` records `ihirfhnpjtetdmdvqvy`.
- `backend/supabase/.temp/pooler-url` records a pooler target whose username
  derives the same `ihirfhnpjtetdmdvqvy` project ref.
- `.vscode/mcp.json` records a Supabase MCP `project_ref` value of
  `ihirfhnpjtetdmdvqvyu`.

Launch interpretation:

- Repo-local targeting evidence remains non-authoritative for production
  database selection.
- Raw secret values MUST NOT be required for production target verification.
- Production target classification is VERIFIED (`DERIVED_RUNTIME_AUTHORITY`)
  when all of the following are satisfied:
  - runtime `DATABASE_URL` resolves to project ref `X`
  - runtime `SUPABASE_URL` resolves to project ref `X`
  - both observations originate from Fly logs or runtime environment
  - `DATABASE_URL` and `SUPABASE_DB_URL` are proven identical by deployed secret digest equality
  - No conflicting project ref is observed across runtime authority surfaces
- When those conditions are satisfied, verification must not classify the target as `BLOCKED`.
- `SUPABASE_PROJECT_REF` is corroborating runtime evidence only when it is
  present and matches the same runtime-derived project ref. Its absence alone
  does not prevent VERIFIED (`DERIVED_RUNTIME_AUTHORITY`).
- If runtime authority surfaces conflict, the production target remains
  unverified until the conflict is reconciled.
- The `.vscode/mcp.json` Supabase MCP target is not production database
  authority.
- `backend/supabase/.temp/*` is repo-local targeting evidence only and is not
  sufficient by itself to prove production database authority.
- Public launch is blocked until production runtime authority resolves to one
  exact Supabase project target through either explicit matching runtime
  configuration or VERIFIED (`DERIVED_RUNTIME_AUTHORITY`).

Backend runtime database authority:

- In Fly cloud runtime, `DATABASE_URL` is the authoritative backend runtime
  connection variable.
- In Fly cloud runtime, `DATABASE_URL` must point to the verified intended
  production Supabase database target.
- In Fly cloud runtime, `DATABASE_URL` must never point to `localhost`,
  `127.0.0.1`, `::1`, `db`, or `host.docker.internal`.
- `SUPABASE_DB_URL` may be used by production verification or migration tooling
  only when it resolves to the same verified intended Supabase project target.
- `MCP_PRODUCTION_DATABASE_URL` and `MCP_PRODUCTION_SUPABASE_DB_URL` are not app
  runtime authority. They may be used only for explicit MCP production-mode
  read-only inspection and must resolve to the same verified intended Supabase
  project target.
- Local `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USER`, and
  `DATABASE_PASSWORD` construction is local runtime authority only. It must not
  become Fly production runtime authority.

## 5. BASELINE REQUIREMENT

- The canonical baseline source is `backend/supabase/baseline_v2_slots/`.
- The canonical baseline lock is `backend/supabase/baseline_v2_slots.lock.json`.
- The canonical baseline lock also carries the per-slot post-state metadata
  required by the production release-command cutover mechanism.
- Non-destructive production slot promotion for Baseline V2 is owned by the
  release-machine cutover defined in
  `actual_truth/contracts/baseline_v2_release_cutover_contract.md`.
- All future Baseline V2 promotions must use the lock-driven release-command
  `N -> N+1` cutover mechanism. Manual production SQL is forbidden.
- Public launch requires the canonical Baseline V2 hosted profile to apply the
  app-owned slot chain and verify the hosted Supabase substrate interface
  against the intended production Supabase database target.
- Full destructive `app`-schema reset is forbidden for production and any
  stateful business environment that must preserve canonical membership,
  purchase, payment, referral, or protected course-access state.
- Hosted Baseline V2 replay may perform destructive app-schema rebuild only for
  an explicitly classified stateless verification target; protected or
  unclassified hosted targets must fail closed.
- Hosted production replay must not create or normalize provider-owned `auth`
  or `storage` schema.
- Public launch requires verification that the production schema matches the
  accepted Baseline V2 app-owned schema hash and substrate interface for every
  launch-critical runtime surface.
- Legacy migration paths are not launch authority when baseline slots are the
  canonical truth.
- `backend/supabase/migrations/` is legacy-only in this repository and must not
  redefine production launch authority.
- Archive migration paths and historical launch reports are reference evidence
  only and cannot override the baseline slot chain.
- Accepted Baseline V2 slots and `backend/supabase/baseline_v2_slots.lock.json`
  are evidence for launch authority; this contract does not authorize editing
  them.

## 6. RUNTIME LAUNCH GATES

Public launch is blocked unless all minimum runtime gates below pass against the
same production deployment and the same verified production Supabase project.

Core runtime gates:

- `GET /healthz` returns success from Fly app `aveli`, process group `app`.
- `GET /readyz` returns success from Fly app `aveli`, process group `app`.
- The app process proves it is not using a local database target in cloud
  runtime.
- The worker process group is running or explicitly classified as not required
  for the MVP launch domain under canonical contract authority.

Public course gates:

- `GET /courses` passes as `course_discovery_surface`.
- `GET /courses/{course_id}` passes as course detail composed of
  `course_discovery_surface` and `lesson_structure_surface`.
- `GET /courses/by-slug/{slug}` passes as course detail composed of
  `course_discovery_surface` and `lesson_structure_surface`.
- Public course surfaces do not expose `lesson_content`, `lesson_media`,
  `enrollment_state`, or `unlock_state`.

Protected access gates:

- Auth registration, login, token refresh, email verification, and onboarding
  completion pass through `auth_onboarding_contract.md`.
- `welcome_pending` is canonical onboarding state and must be represented in
  the deployed baseline authority.
- App entry requires completed onboarding and active membership under
  `onboarding_entry_authority_contract.md`.
- Membership app-entry state passes through `app.memberships` under
  `commerce_membership_contract.md`.
- Protected lesson content access passes only through `course_enrollments` and
  `lesson.position <= current_unlock_position` under `course_access_contract.md`.

Media gates:

- Media identity is owned by `app.media_assets`.
- Source tables own governed media inclusion and placement truth.
- `app.runtime_media` remains read-only projection authority where in scope.
- Backend read composition owns final frontend-facing media representation.
- Profile/community media is canonical Baseline V2 scope.
- `app.profile_media_placements` owns profile/community authored-placement
  truth.
- `app.profiles` remains projection-only.
- `app.home_player_course_links` is source truth for course-linked home-audio
  inclusion.
- Course-linked home-audio output is owned by backend composition as read
  authority, not by treating `runtime_media` as the mandatory direct source
  table for `app.home_player_course_links`.
- No media launch path may resolve directly through Supabase Storage as business
  truth.
- Worker-owned media processing required for MVP launch must be verified in the
  worker process group.

Payment gates:

- Membership purchase initiation, course purchase initiation, Stripe webhook
  completion, and post-payment membership/course-access mutations pass through
  `commerce_membership_contract.md`, `course_monetization_contract.md`, and
  `course_access_contract.md`.
- Stripe remains payment processor and event emitter only.
- Provider checkout/session/subscription/payment state is provider correlation
  only and is not Aveli domain authority.
- `subscription` may remain provider/order modality, but not Aveli domain
  authority.
- Service/session/Connect-like order fields remain inert unless later activated
  by explicit accepted authority.
- Frontend payment success must not become membership or course-access authority.

LiveKit gates:

- LiveKit is paused/inert under `livekit_runtime_contract.md`.
- Public launch must not require active LiveKit runtime behavior unless a later
  accepted LiveKit activation authority explicitly promotes it into launch
  scope.
- Production launch is blocked if LiveKit webhook ingestion, enqueueing, worker
  processing, retry, deletion, or domain mutation is active without later
  accepted activation authority.

Language and prompt gates:

- User-facing product text must be Swedish.
- Generated operator prompts must be copy-paste-ready English.
- Stale docs, missing docs, README text, historical launch reports, or local
  operator notes must not become production deployment authority.

## 7. CREDENTIAL SAFETY

- Public launch is blocked if any production database credential has been
  exposed outside the approved secret store.
- Public launch is blocked until exposed production database credentials are
  rotated and all old connection strings are removed from runtime authority.
- Raw secret values are not required when runtime connection identity and
  deployed secret digests already prove the production target.
- Public launch is blocked if runtime authority surfaces or deployed digests
  disagree on the intended Supabase project target.
- Public launch is blocked if runtime `SUPABASE_PROJECT_REF` and runtime
  `SUPABASE_URL` disagree or cannot be derived to the same project ref.
- Public launch is blocked if stale Supabase project refs remain in canonical
  production runtime configuration.
- No credential or connection string in `.vscode/`, `.temp/`, archive material,
  local env files, shell history, or audit output may remain authoritative for
  production runtime.

## 8. VERIFICATION TARGET

The production deployment contract is satisfied only when all are true:

- Fly app `aveli` has separate verified `app` and `worker` process groups.
- The `app` process serves only the HTTP/API runtime and passes `/healthz` and
  `/readyz`.
- The `app` process does not launch local background workers in cloud runtime.
- The `worker` process group is verified separately for launch-required worker
  domains.
- The intended Supabase production project target is explicit and exact.
- Production database authority resolves to one exact Supabase project either
  through explicit matching runtime configuration or VERIFIED
  (`DERIVED_RUNTIME_AUTHORITY`).
- Raw secret values are not required when runtime `DATABASE_URL`,
  runtime `SUPABASE_URL`, and deployed `DATABASE_URL` / `SUPABASE_DB_URL`
  digest equality already prove the target.
- Production runtime cannot fall back to local database configuration.
- The current `backend/supabase/baseline_v2_slots.lock.json` hosted profile is
  applied and verified against the intended production Supabase project.
- Any required production slot delta is executed only through the accepted
  lock-driven release-command `N -> N+1` cutover path before app and worker
  Machines update.
- Legacy migration paths do not define launch authority.
- Minimum public, protected, media, payment, home-audio, profile/community
  media, and onboarding surfaces pass under the Baseline V2 freeze contract and
  updated domain contracts.
- LiveKit remains paused/inert unless a later accepted activation authority
  explicitly changes its production launch status.
- Provider checkout/session/subscription/payment state is not treated as Aveli
  domain authority.
- User-facing product text is Swedish.
- Generated operator prompts are copy-paste-ready English.
- Exposed or stale production database credentials have been rotated and old
  connection strings are not runtime authority.
- Deployment fails closed on any mismatch with the Baseline V2 freeze contract,
  accepted baseline authority, production database authority, domain contracts,
  or credential safety rules.
