# TASK ID: CEG-001A

## TITLE
Canonical Course Description Authority Introduction

## TYPE
OWNER

## TASK_TYPE
BASELINE_SUBSTRATE_AUTHORITY

## DOMAIN TAG
course-entry-gateway

## STATUS
DONE

## APPROVAL REVIEW
Approved on 2026-04-26 as a deterministic owner task for the missing Course Entry/Gateway full-description substrate.

Review scope:

- task definition only
- no backend runtime implementation
- no frontend runtime implementation
- no baseline SQL change
- no test change

Evidence reviewed:

- `codex/AVELI_OPERATING_SYSTEM.md`
- `codex/AVELI_EXECUTION_WORKFLOW.md`
- `actual_truth/contracts/course_public_surface_contract.md`
- `actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md`
- `actual_truth/contracts/system_text_authority_contract.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- `backend/supabase/baseline_v2_slots/V2_0004_courses_and_public_content.sql`
- `backend/supabase/baseline_v2_slots/V2_0010_read_projections.sql`
- `backend/supabase/baseline_v2_slots/V2_0018_course_access_classification.sql`

Approval decision:

- CEG-001A is approved for future execution inside its declared mutation plane.
- CEG-001A does not approve Course Entry/Gateway runtime implementation.
- CEG-002 remains blocked until CEG-001A is executed and verification proves the full description substrate exists in clean Baseline V2 replay.

## DEPENDS_ON
["CEG-001"]

## BLOCKS
["CEG-002"]

## MODE FOR FUTURE EXECUTION
execute

## MUTATION PLANE FOR FUTURE EXECUTION
Contracts and append-only Baseline V2 substrate only.

Future execution MUST NOT modify backend runtime code, frontend runtime code, tests, existing accepted baseline slots, production migrations, or live data unless a later approved task explicitly expands scope.

## PROBLEM STATEMENT
The Course Entry/Gateway contract requires a full course `description` payload.

Clean Baseline V2 currently materializes `app.course_public_content.short_description` only. No canonical full course description field exists in the accepted baseline substrate.

Because the Course Entry/Gateway read model requires `description`, and no canonical persisted field currently owns that value, CEG-002 is BLOCKED until this authority-to-substrate chain exists.

Files such as `description.md` are not runtime truth and cannot satisfy the Course Entry/Gateway contract directly.

## AUTHORITY DECISION
Canonical runtime field:

- `app.course_public_content.description`

Canonical owner:

- backend course domain authority

Forbidden owners:

- frontend
- local files
- markdown files
- editor preview state
- imported manifests
- route-local fallback text

`description.md` boundary:

- `description.md` MAY be used only as ingestion/source material.
- `description.md` MUST NOT be runtime authority.
- Learner runtime, frontend runtime, Course Entry/Gateway resolver, Lesson View, Preview, and public API reads MUST NOT read `description.md` as truth.
- After ingestion, the database field `app.course_public_content.description` is canonical.

## DATA MODEL REQUIREMENT
Future execution MUST introduce an append-only Baseline V2 slot:

- slot name pattern: `V2_00XX_*`
- required column: `description TEXT NOT NULL DEFAULT ''`
- canonical table: `app.course_public_content`

The substrate change MUST be append-only. Existing accepted baseline slots MUST NOT be edited.

Existing `short_description` authority MUST remain intact as preview/summary public course content.

## INGESTION RULE
Canonical ingestion flow:

```text
description.md -> ingestion pipeline -> app.course_public_content.description
```

Rules:

- ingestion is one-way
- DB is canonical after ingestion
- ingestion tooling may read `description.md` only to populate the DB field
- runtime reads MUST use backend read composition over DB state
- no frontend markdown parsing is allowed for course descriptions

## READ MODEL REQUIREMENT
The Course Entry/Gateway endpoint:

```text
GET /courses/{course_id_or_slug}/entry-view
```

MUST expose both:

- `description`: full course description from `app.course_public_content.description`
- `short_description`: preview/summary from `app.course_public_content.short_description`

The frontend MUST render these backend-authored fields only. It MUST NOT parse markdown files, derive full descriptions from short descriptions, or synthesize missing descriptions.

## CONTRACT ALIGNMENT
This task aligns the missing substrate with:

- `actual_truth/contracts/system_text_authority_contract.md`
- `actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md`
- `actual_truth/contracts/course_public_surface_contract.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`

Required contract interpretation:

- course descriptions are `db_domain_content`
- Course Entry/Gateway is backend-owned
- backend read composition delivers the course description
- frontend is render-only
- missing description authority fails closed

No contract may classify `description.md`, frontend logic, local files, or markdown parsing as runtime description authority.

## DEPENDENCY PLACEMENT
This task MUST run after CEG-001 contract owner work and before CEG-002 can pass.

Dependency edge:

```text
CEG-001 -> CEG-001A -> CEG-002
```

CEG-002 and any downstream Course Entry/Gateway implementation work MUST remain blocked until this task is reviewed, approved, executed, and verified.

## VERIFICATION REQUIREMENT
CEG-001A execution verification MUST prove:

- clean Baseline V2 replay succeeds
- `app.course_public_content.description` exists
- `app.course_public_content.description` is `TEXT NOT NULL DEFAULT ''`
- existing `app.course_public_content.short_description` remains intact
- no frontend markdown parsing exists for course descriptions
- no runtime path treats `description.md` as authority
- no contract conflicts with `system_text_authority_contract.md`
- no existing accepted baseline slot was modified

Downstream CEG-002/runtime verification MUST prove:

- Course Entry/Gateway endpoint returns both `description` and
  `short_description`
- Course Entry/Gateway reads `description` through backend read composition
  from `app.course_public_content.description`
- frontend remains render-only and does not parse markdown or synthesize
  course descriptions

## STOP CONDITIONS
STOP if any of the following are true:

- canonical owner for full course description is unclear
- `description.md` is proposed as runtime authority
- frontend parsing or fallback is proposed for full course description
- the baseline change cannot be introduced append-only
- existing accepted baseline slots would need mutation
- `short_description` semantics would be changed or overwritten
- Course Entry/Gateway implementation begins before the description substrate exists
- contract text classifies description authority outside `db_domain_content` and backend read composition

## EXPECTED OUTCOME
The system has an explicit owner task for the missing full course description substrate required by Course Entry/Gateway.

After this task is executed, CEG-002 may be replayed against a baseline where the Course Entry/Gateway `description` field has canonical DB authority.

## EXECUTION NOTES
Executed on 2026-04-26 inside the approved mutation plane.

Files changed:

- `backend/supabase/baseline_v2_slots/V2_0035_course_public_description_substrate.sql`
- `backend/supabase/baseline_v2_slots.lock.json`
- `actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md`
- `actual_truth/contracts/course_public_surface_contract.md`
- `actual_truth/contracts/system_text_authority_contract.md`
- `actual_truth/DETERMINED_TASKS/CEG-001A_canonical_course_description_authority_introduction.md`

Execution result:

- Added append-only Baseline V2 slot `V2_0035_course_public_description_substrate.sql`.
- Added `app.course_public_content.description text not null default ''`.
- Preserved `app.course_public_content.short_description`.
- Updated the Baseline V2 lock to accept slot 35 and schema hash `549d4aba48a803c9c888d77f23365aea9d77c1d40578f447e6de149d4f8cb60b`.
- Aligned course and text contracts so full course descriptions are backend-owned `db_domain_content`.
- Kept Course Entry/Gateway runtime implementation out of scope.

Verification performed:

- `.\.venv\Scripts\python.exe -m json.tool backend\supabase\baseline_v2_slots.lock.json`
- `.\.venv\Scripts\python.exe ops\check_baseline_slots.py`
- isolated clean Baseline V2 replay through `backend.bootstrap.baseline_v2.ensure_v2_baseline`
- `.\.venv\Scripts\python.exe -m pytest backend\tests\test_bootstrap_baseline_v2.py backend\tests\test_baseline_v2_authority_lock.py -q`
- `.\.venv\Scripts\python.exe -m pytest backend\tests\test_baseline_v2_cutover_lock_replay.py -q`
- runtime-scope search for forbidden `description.md` authority in `backend/app`, `frontend/lib`, and existing baseline slots
- `git diff --check`

Verification result:

- PASS for CEG-001A substrate and contract-authority scope.
- Runtime Course Entry/Gateway endpoint verification is deferred to CEG-002 because CEG-001A forbids backend runtime implementation.

## NEXT STEP
Replay CEG-002 Baseline/Substrate Gate against the new slot 35 substrate before Course Entry/Gateway runtime implementation begins.
