# Legacy Deviation Processing Workflow

## Authority Boundary

This workflow uses the legacy outrooting foundation as the canonical starting inventory.

The only starting inventory artifacts are:

- `DRIFT_MANIFEST.json`
- `DRIFT_REGISTER.md`
- `OUTROOTING_PRIORITY_MAP.md`
- `CANONICAL_VS_NONAUTHORITATIVE_BOUNDARY.md`

Canonical authority remains grounded only in:

- the four foundation artifacts above
- the canonical source set already recognized by `CANONICAL_VS_NONAUTHORITATIVE_BOUNDARY.md`

This workflow does not reinterpret canonical authority.

This workflow does not authorize implementation by itself.

## Program Entry Rule

Every future deviation-family run must begin in this order:

1. no-code audit first
2. review findings against the foundation inventory and canonical boundary
3. run the deterministic workflow below
4. stop before implementation unless a separate later task explicitly authorizes execution

Program constraint:

- no code changes are performed by this workflow definition run
- no DB mutations are performed by this workflow definition run
- no drift-register expansion occurs in this workflow definition run

## 1. Deterministic Processing Loop For A Drift Item

Each registered drift item begins as a seed deviation.

Each seed deviation must be processed through the same loop:

1. `canonical diff`
   - compare the seed deviation against the canonical boundary, the canonical rule references already attached to the seed, and the canonical source set named by the boundary document
   - identify the exact authority mismatch without expanding scope by assumption
   - explicitly name:
     - the protected canonical path
     - the non-authoritative surface
     - the doctrine being violated
   - output:
     - seed deviation doctrine statement
     - protected canonical path statement
     - provisional family boundary
2. `semantic discovery`
   - run the mandatory search pack across GitHub and repo surfaces
   - search for semantically similar helpers, aliases, payloads, schema terms, migration echoes, tests, frontend mirrors, and generated echoes
   - output:
     - candidate sibling deviations
     - candidate near-siblings
     - candidate alias and terminology echoes
3. `sibling-pattern expansion`
   - group discovered candidates into the same deviation family only when the evidence shows the same non-canonical doctrine outside the protected canonical boundary
   - reject candidates that are canonical, boundary-protected historical structure, or unsupported by evidence
   - output:
     - family working set
     - excluded findings ledger
4. `deterministic classification`
   - classify every family member using the mandatory fields in Section 4
   - assign one primary processing state per discovered deviation
   - output:
     - family classification ledger
     - per-member state assignment
5. `execution planning`
   - define the smallest safe mutation set that removes, collapses, isolates, or fences the non-authoritative doctrine without touching canonical authority
   - define verification gates before any mutation begins
   - output:
     - execution-ready family plan
     - pre-mutation verification checklist
6. `minimal safe mutation`
   - this step belongs to a later explicitly authorized execution run, not to this workflow-definition run
   - mutate only the smallest justified surface
   - mutate one deviation family at a time
   - if new sibling evidence appears, stop and reopen the loop instead of absorbing scope mid-mutation
7. `post-mutation reverification`
   - re-check the family against the canonical boundary and the family plan
   - verify that the intended canonical path still owns the concept
   - output:
     - post-mutation evidence set
     - closure candidacy result
8. `repeated semantic search`
   - repeat the mandatory search pack after mutation and after reverification
   - search again for sibling deviations, near-siblings, alias echoes, and hidden doctrine repetitions
   - if new evidence appears, reopen the loop at `canonical diff`
   - if no new evidence appears and reverification passes, move the family toward closure

Loop rules:

- deep semantic search across GitHub and repo surfaces is mandatory between each major step
- new sibling evidence always reopens the loop
- canonical uncertainty always blocks mutation
- mutation never proceeds from classification directly to implementation without a fresh search gate in between

## 2. Deviation Family

The processing unit is a deviation family, not just a single file occurrence.

### Seed Deviation

The registered drift item from `DRIFT_REGISTER.md` and `DRIFT_MANIFEST.json`.

It is the first confirmed member of the family.

### Sibling Deviation

A new deviation that qualifies for the same family only if all are true:

- it repeats the same non-canonical doctrine or authority shadow
- it conflicts with the same protected canonical path or rule family
- it sits outside the locked canonical boundary
- it is evidenced by search rather than guesswork

### Near-Sibling Deviation

A deviation that is not identical in shape, but still appears to carry the same legacy doctrine, alias, transition logic, or fallback behavior.

Near-siblings enter the family working set only after evidence confirms they belong to the same doctrine family.

### Alias Or Terminology Echo

A different term, helper name, payload key, route label, model name, or generated artifact name that preserves the same retired doctrine.

Echo classes include:

- old term versus canonical term
- legacy field versus canonical field
- helper name versus canonical concept name
- generated frontend model echo of a backend legacy field
- schema alias of a retired surface

### Cross-Surface Echo

The same doctrine repeated across different system layers, including:

- schema echoes
- test echoes
- frontend echoes
- backend echoes
- migration echoes
- script and cleanup-tool echoes

### Family Expansion Rule

- new evidence may expand a family working set
- new evidence does not automatically rewrite the drift register
- formal drift-register expansion must happen only in a separate evidence-backed generate step if the newly discovered deviations qualify for canonized inventory update

### Current Registered Seed Families

The current seed families from the canonical starting inventory are:

- `DRIFT-001`: Stripe-era membership compatibility family
- `DRIFT-002`: remote-schema and legacy migration doctrine family
- `DRIFT-003`: raw-table lesson and media helper family
- `DRIFT-004`: alternate home-audio playback-shaping family
- `DRIFT-005`: retired `teacher_profile_media` cleanup and migration residue family
- `DRIFT-006`: legacy media payload and verification residue family

## 3. Mandatory Search Behavior Between Steps

Between every major processing step, the workflow must run a mandatory search pack across both GitHub and local repo surfaces.

The search pack has five required components.

### A. Exact Lexical Search

Search for the exact seed terms, field names, payload keys, helper names, route names, file names, and SQL objects already attached to the family.

Purpose:

- find exact repetitions
- find direct reuse
- find generated echoes

### B. Semantic Search

Search for conceptually similar code and doctrine using semantic retrieval over repository and GitHub surfaces.

Purpose:

- find non-obvious siblings
- find structurally similar transition layers
- find fallback logic using different names
- find hidden doctrine repetitions before execution continues

### C. Symbol And Path Search

Search by function name, class name, schema object, path fragment, route fragment, import path, and generated model path.

Purpose:

- find call chains
- find adjacent helpers
- find mirrored path surfaces

### D. Synonym And Doctrine Search

Search for legacy-versus-canonical term pairs and doctrine synonyms.

Purpose:

- find alias echoes
- find terminology drift
- find indirect restatements of the same non-canonical model

### E. Hidden Repetition Search

Search for hidden repetitions of the same pattern across:

- backend
- frontend
- tests
- migrations
- schema-adjacent files
- scripts and cleanup tooling
- generated artifacts

Purpose:

- prevent under-scoped mutation
- discover sibling deviations and near-siblings before execution continues

### Search Surfaces

The search pack must cover:

- local repository search
- GitHub code search or equivalent GitHub-indexed retrieval surface used by the program
- generated and mirrored artifacts when they exist
- test and migration surfaces even when the seed deviation began elsewhere

### Mandatory Search Gates

The search pack must run:

- after `canonical diff`
- after `semantic discovery`
- after `sibling-pattern expansion`
- after `deterministic classification`
- after `execution planning` and before any mutation
- after `post-mutation reverification`

Search-gate rules:

- if the search pack finds new family members, the loop reopens before mutation continues
- if the search pack finds only canonical surfaces inside the locked boundary, those findings are recorded and excluded from mutation scope
- if a required search surface is unavailable, mutation cannot begin until the family is re-scoped or the search gap is resolved

### Search Ledger Requirement

Every search gate must record:

- `family_id`
- `seed_drift_id`
- `search_step`
- `search_type`
- `query_or_concept`
- `surface_searched`
- `hits`
- `included_findings`
- `excluded_findings`
- `reason_for_exclusion`

## 4. Deterministic Classification

Every discovered deviation must be classified using the fields below.

### canonical_path_exists

Allowed values:

- `YES_DIRECT`
- `YES_ADJACENT`
- `NO`
- `UNKNOWN`

Meaning:

- `YES_DIRECT`: the canonical replacement path already exists for the same concept and same operational role
- `YES_ADJACENT`: the canonical path exists for the concept, but not yet as a direct drop-in for the discovered deviation
- `NO`: no canonical replacement path is evidenced for that exact role
- `UNKNOWN`: evidence is insufficient and mutation must not proceed

### authority_risk

Allowed values:

- `HIGH`
- `MEDIUM`
- `LOW`

Meaning:

- `HIGH`: the deviation can reintroduce shadow authority, mounted bypass, or thick transition doctrine
- `MEDIUM`: the deviation is non-authoritative today but can mislead future work or become mounted again
- `LOW`: the deviation is residual and does not currently change runtime truth

### transition_layer

Allowed values:

- `NONE`
- `THIN`
- `THICK`

Meaning:

- `NONE`: no meaningful transition layer, only a direct dead or duplicate surface
- `THIN`: small alias, compatibility bridge, or terminology echo
- `THICK`: multi-surface translation, payload, helper, or doctrine layer

### residual_value

Allowed values:

- `ACTIVE_NONAUTHORITATIVE`
- `CONDITIONALLY_REACHABLE`
- `HISTORICAL_ONLY`
- `DEAD`

Meaning:

- `ACTIVE_NONAUTHORITATIVE`: still active outside canonical authority and can influence behavior or future work
- `CONDITIONALLY_REACHABLE`: not mounted as primary truth, but still callable, importable, or reusable
- `HISTORICAL_ONLY`: only historical or explanatory residual value remains
- `DEAD`: no remaining justified value is evidenced

### primary_processing_state

Allowed values:

- `REPLACE_WITH_CANONICAL_PATH`
- `COLLAPSE_TRANSITION_LAYER`
- `ISOLATE_NON_AUTHORITATIVE_SURFACE`
- `REMOVE_DEAD_SURFACE`

Assignment rules:

- choose `REPLACE_WITH_CANONICAL_PATH` when `canonical_path_exists = YES_DIRECT` and the deviation directly shadows canonical truth
- choose `COLLAPSE_TRANSITION_LAYER` when the deviation is mainly a compatibility bridge, alias system, payload mapper, or translation layer
- choose `ISOLATE_NON_AUTHORITATIVE_SURFACE` when the deviation cannot yet be removed safely but must be fenced away from mounted authority
- choose `REMOVE_DEAD_SURFACE` when the deviation has no justified residual value
- if `canonical_path_exists = UNKNOWN`, mutation is blocked and the family returns to discovery and classification

### Classification Ledger Requirement

Every discovered deviation must have a ledger row containing:

- `family_id`
- `seed_drift_id`
- `deviation_scope`
- `canonical_path_exists`
- `authority_risk`
- `transition_layer`
- `residual_value`
- `primary_processing_state`
- `canonical_rule_reference`
- `classification_evidence`

## 5. Allowed Processing States

### REPLACE_WITH_CANONICAL_PATH

Use when the canonical path is already present and the deviation is a duplicate, bypass, or shadow of that path.

Execution goal:

- delete, redirect, or replace the deviation so only the canonical path remains active for that concept

### COLLAPSE_TRANSITION_LAYER

Use when the deviation exists as a compatibility bridge, alias doctrine, or multi-surface translation layer around a canonical path.

Execution goal:

- shrink the transition doctrine until the non-canonical layer no longer survives as an independent behavioral model

### ISOLATE_NON_AUTHORITATIVE_SURFACE

Use when the deviation cannot yet be safely removed, but must be fenced so it cannot act as live authority.

Execution goal:

- preserve safety while preventing the surface from re-entering mounted or future authority paths

### REMOVE_DEAD_SURFACE

Use when the deviation has no justified residual value.

Execution goal:

- remove the dead surface completely

## 6. When Replacement Is Not Possible

Replacement is not possible when:

- `canonical_path_exists = NO`
- `canonical_path_exists = YES_ADJACENT` but the deviation still performs an unmatched role
- `canonical_path_exists = UNKNOWN`
- mutation would cross into the locked canonical boundary

When replacement is not possible, the workflow must do all of the following:

1. route the deviation into one of:
   - `COLLAPSE_TRANSITION_LAYER`
   - `ISOLATE_NON_AUTHORITATIVE_SURFACE`
   - `REMOVE_DEAD_SURFACE`
2. record a blocker entry in the family ledger
3. define the next condition under which replacement candidacy may be re-evaluated

### Blocker Record

Every blocker record must contain:

- `family_id`
- `seed_drift_id`
- `deviation_scope`
- `replacement_blocker_reason`
- `blocking_evidence`
- `current_processing_state`
- `future_replacement_trigger`

### Routing Rules

- if the deviation still carries meaningful compatibility translation, route to `COLLAPSE_TRANSITION_LAYER`
- if the deviation is reachable but not safe to delete, route to `ISOLATE_NON_AUTHORITATIVE_SURFACE`
- if the deviation has no justified residual value, route to `REMOVE_DEAD_SURFACE`
- if `canonical_path_exists = UNKNOWN`, stop mutation and return to discovery and classification

### Future Replacement Candidacy

Replacement candidacy may be re-evaluated only when:

- a later family closure removes the blocker
- a new canonical path is evidenced without reinterpretation
- repeated search shows the deviation no longer performs a distinct role
- boundary review confirms replacement can occur without touching protected canonical authority

## 7. Stop Conditions

### A. Family Fully Discovered

A deviation family is considered fully discovered only when all are true:

- the mandatory search pack has run across all required surfaces
- no new sibling, near-sibling, alias echo, or cross-surface echo is found in two consecutive search rounds after the last family-scope change
- canonical-boundary exclusions have been recorded explicitly
- every retained family member is evidence-backed

### B. Execution May Begin

Execution may begin only when all are true:

- the family is fully discovered
- every family member has a completed deterministic classification
- every family member has one primary processing state
- the protected canonical path is explicitly named
- the mutation scope is minimal and bounded
- verification criteria are defined
- a final pre-mutation search gate finds no net-new family members

### C. Processed Family Closed

A processed family is considered closed only when all are true:

- the planned mutation finished
- post-mutation reverification passed
- repeated semantic and lexical search finds no surviving active sibling doctrine in scope
- any intentionally isolated residual surface is explicitly fenced and recorded as non-authoritative
- no canonical boundary breach occurred

## Program Progression Rule

The outrooting program processes family after family through the same loop.

If the workflow continues to discover sibling deviations and hidden doctrine echoes while preserving the canonical boundary, the next valid step is to apply this workflow to the first highest-risk seed family already identified by the foundation inventory.

From the current priority map, the first highest-risk candidate family is:

- `DRIFT-002`: remote-schema and legacy migration lineage still encode non-canonical doctrine

This workflow-definition run stops before implementation.
