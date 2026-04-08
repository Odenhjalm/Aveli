# AOI-012 AGGREGATE CONTRACT SURFACE GATE

TYPE: `AGGREGATE`  
TASK_TYPE: `TEST_ALIGNMENT`  
DEPENDS_ON: `["AOI-011"]`

## Goal

Run a final aggregate gate over contracts, baseline slots, backend routes, frontend consumers, and tests.

## Required Checks

- canonical route inventory only
- canonical baseline object inventory only
- canonical failure envelope only
- referral separation preserved
- teacher-request lifecycle absent
- avatar-write authority absent
- runtime schema introspection absent

## Exit Criteria

- the repo exposes one coherent Auth + Onboarding authority model
- no contract-scope gap remains before implementation execution begins
