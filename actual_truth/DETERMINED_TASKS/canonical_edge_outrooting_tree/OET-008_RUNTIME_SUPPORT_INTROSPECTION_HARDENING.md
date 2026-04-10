# OET-008 RUNTIME SUPPORT INTROSPECTION HARDENING

- TYPE: `OWNER`
- GROUP: `ACTIVE AUXILIARY DRIFT`
- REQUIRED BEFORE FUTURE CORE FEATURE WORK: `NO`
- EXECUTION CLASS: `OPTIONAL LATER HARDENING`

## Problem Statement

Active support surfaces still use `information_schema` probes or tolerant undefined-column handling as runtime-adjacent behavior.

These paths are not currently the canonical core, but they remain a drift risk if left implicit.

## Contract References

- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)

## Audit Inputs

- `OEA-09`

## Implementation Surfaces Affected

- `backend/app/repositories/media_assets.py`
- `backend/app/services/domain_observability/user_inspection.py`
- `backend/tests/test_domain_media_inspection.py`
- `backend/tests/test_domain_observability_mcp.py`

## Depends On

- `OET-011`

## Acceptance Criteria

- no scoped runtime-adjacent support path uses schema introspection as authority or hidden fallback logic
- any surviving introspection in scope is explicit, bounded, and non-authoritative
- support paths do not reinterpret canonical media, auth, or commerce truth

## Stop Conditions

- stop if the task would mutate baseline or canonical runtime core to satisfy support-tooling cleanup
- stop if support surfaces still silently tolerate missing canonical fields as a fallback authority pattern
- stop if the task expands beyond the scoped support surfaces

## Out Of Scope

- mounted studio, events, or auth cleanup
- dormant route quarantine
- contract changes
