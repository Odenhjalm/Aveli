# PRODUCTION DEPLOYMENT CONTRACT

## STATUS

ACTIVE

This contract defines the canonical production deployment authority for Aveli.
It operates under `SYSTEM_LAWS.md`, `supabase_integration_boundary_contract.md`,
`auth_onboarding_contract.md`, `commerce_membership_contract.md`,
`course_access_contract.md`, `course_public_surface_contract.md`, and
`media_pipeline_contract.md`.

This contract owns production deployment authority only. It does not redefine
Supabase substrate law, baseline schema law, auth/onboarding law, commerce law,
course-access law, or media law.

## 1. CONTRACT LAW

- The authoritative Fly production app is `aveli`.
- Production runtime means the Fly app `aveli` with `APP_ENV=production`.
- Production runtime database selection is owned by backend runtime environment,
  not by local developer defaults, legacy migration state, or ad hoc scripts.
- Production launch is blocked unless the canonical baseline slot chain
  `0001` through `0033` has been applied to the intended production Supabase
  database target and verified against the contract set.
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

- The production Supabase project-selection authority is `SUPABASE_PROJECT_REF`
  only when it matches both `SUPABASE_URL` and the production database
  URL-derived project ref.
- The intended production Supabase project is `UNVERIFIED` until
  `SUPABASE_PROJECT_REF`, `SUPABASE_URL`, and the production database URL-derived
  project ref all match exactly.
- If `SUPABASE_PROJECT_REF` is absent or mismatched, no other repo-local value
  may become production project authority.
- The `.vscode/mcp.json` Supabase MCP target is not production database
  authority.
- `backend/supabase/.temp/*` is repo-local targeting evidence only and is not
  sufficient by itself to prove production database authority.
- Public launch is blocked until the Supabase project-ref mismatch is resolved
  and the intended production project is written into the launch environment as
  matching `SUPABASE_PROJECT_REF`, `SUPABASE_URL`, and production `DATABASE_URL`
  / `SUPABASE_DB_URL` target evidence.

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

- The canonical baseline source is `backend/supabase/baseline_slots/`.
- The canonical baseline lock is `backend/supabase/baseline_slots.lock.json`.
- Public launch requires the baseline slot chain `0001` through `0033` to be
  applied and verified against the intended production Supabase database target.
- Public launch requires verification that the production schema matches the
  accepted `0001` through `0033` baseline authority for every launch-critical
  runtime surface.
- Legacy migration paths are not launch authority when baseline slots are the
  canonical truth.
- `backend/supabase/migrations/` is legacy-only in this repository and must not
  redefine production launch authority.
- Archive migration paths and historical launch reports are reference evidence
  only and cannot override the baseline slot chain.

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
- App entry requires completed onboarding and active membership under
  `onboarding_entry_authority_contract.md`.
- Membership app-entry state passes through `app.memberships` under
  `commerce_membership_contract.md`.
- Protected lesson content access passes only through `course_enrollments` and
  `lesson.position <= current_unlock_position` under `course_access_contract.md`.

Media gates:

- Media identity, placement, runtime state, and frontend representation follow
  the canonical chain:
  `app.media_assets -> app.lesson_media -> app.runtime_media -> backend read composition -> API -> frontend`.
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
- Frontend payment success must not become membership or course-access authority.

## 7. CREDENTIAL SAFETY

- Public launch is blocked if any production database credential has been
  exposed outside the approved secret store.
- Public launch is blocked until exposed production database credentials are
  rotated and all old connection strings are removed from runtime authority.
- Public launch is blocked if `DATABASE_URL`, `SUPABASE_DB_URL`,
  `MCP_PRODUCTION_DATABASE_URL`, or `MCP_PRODUCTION_SUPABASE_DB_URL` disagree on
  the intended Supabase project target.
- Public launch is blocked if `SUPABASE_PROJECT_REF` and `SUPABASE_URL` disagree
  or cannot be derived to the same project ref.
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
- `SUPABASE_PROJECT_REF`, `SUPABASE_URL`, production `DATABASE_URL`, and any
  production verification `SUPABASE_DB_URL` resolve to the same Supabase project.
- Production runtime cannot fall back to local database configuration.
- Baseline slots `0001` through `0033` are applied and verified against the
  intended production Supabase project.
- Legacy migration paths do not define launch authority.
- Minimum public, protected, media, and payment surfaces pass under their
  existing canonical contracts.
- Exposed or stale production database credentials have been rotated and old
  connection strings are not runtime authority.
