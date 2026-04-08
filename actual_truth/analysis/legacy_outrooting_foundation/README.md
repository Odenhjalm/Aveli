# Legacy Outrooting Foundation

This artifact set was generated after baseline completion reached `FINAL_CANONICAL_BASELINE_COMPLETION_LOCKED` in `BCP-051_aggregate_canonical_authority_completion.md`.

Baseline completion is finished within scope. The locked canonical baseline authority is the append-only slot chain in `backend/supabase/baseline_slots/`, protected by `backend/supabase/baseline_slots.lock.json`, with accepted post-protected additions through slots `0013` through `0019` as confirmed by `BCP-050_aggregate_append_only_and_substrate_audit.md`.

This package captures only non-blocking drift that was actually observed during baseline completion work and aggregate audit. It does not treat remaining legacy code, runtime helpers, migration residue, or compatibility payloads as canonical merely because they still exist in repository or runtime-adjacent surfaces.

No implementation, schema mutation, replay, outrooting, task execution, or full-system diff was performed in this run. The output is analysis-only and is intended to be the authoritative starting point for the upcoming large-scale legacy outrooting effort.

## Included Artifacts

- `DRIFT_REGISTER.md`: deduplicated drift register with per-item metadata, canonical-rule links, and evidence.
- `DRIFT_MANIFEST.json`: machine-readable version of the registered drift items.
- `OUTROOTING_PRIORITY_MAP.md`: sequencing guidance for the future outrooting tree.
- `CANONICAL_VS_NONAUTHORITATIVE_BOUNDARY.md`: explicit boundary between locked canonical baseline authority and remaining non-authoritative drift.

## Inclusion Rule

A drift item is included only if all of the following are true:

1. It was explicitly observed during baseline execution or aggregate audit.
2. It did not block baseline completion.
3. It is not part of the locked canonical authority path.
4. It remains relevant for later legacy outrooting, code alignment, runtime cleanup, or migration cleanup.

## Exclusions

- Hypothetical drift that was not observed in the locked baseline evidence.
- Blockers that were already resolved inside the baseline plan.
- Canonical append-only baseline additions themselves.
- Duplicate items that do not add distinct root-cause scope.

## Summary

- Baseline authority status: `FINAL_CANONICAL_BASELINE_COMPLETION_LOCKED`
- Deduplicated residual drift items: `6`
- Drift foundation scope: non-blocking legacy, runtime-adjacent, repository, and migration residue only
- Next intended use: foundation input for the large outrooting work, not a license to alter locked canonical baseline authority
