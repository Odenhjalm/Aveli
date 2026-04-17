# SYSTEM LAWS

STATUS: ACTIVE

This document is the canonical contract-layer home for cross-domain system laws inside `actual_truth/contracts/`.

## 1. Contract Authority Law

- Every rule family inside `actual_truth/contracts/` must have exactly one canonical location.
- No contract may claim authority over a rule owned by another contract layer or contract file.
- Higher-layer contract authority overrides lower-layer restatement.
- Domain contracts may define only their domain-owned rules.
- Execution contracts may define only execution-owned response-shape law.
- No contract may rely on fallback authority when the canonical owner is available.
- Post-auth entry authority has exactly one canonical owner:
  `onboarding_entry_authority_contract.md`.
- `onboarding_entry_authority_contract.md` is the only contract allowed to
  define post-auth entry composition, post-auth routing authority, or
  current-user entry authority.
- All other contracts may reference entry authority, but must not define or
  redefine:
  - entry composition
  - routing authority
  - alternate current-user entry surfaces
- Any statement outside `onboarding_entry_authority_contract.md` that appears
  to define, duplicate, or override entry authority is non-authoritative and
  must defer to `onboarding_entry_authority_contract.md`.

## 2. Reference And Deprecation Law

- Reference-only files define zero rules.
- Deprecated files define zero rules.
- Generated mirrors, analysis artifacts, archive artifacts, and bundles are non-authoritative.
- Non-authoritative material may point to canonical contracts but may not restate or reinterpret them.

## 3. Cross-Domain Media Law

- Governed media must operate under one shared cross-domain media doctrine.
- `app.media_assets` is the only canonical media identity authority.
- Source tables own governed media inclusion and placement truth.
- `app.runtime_media` is read-only projection authority where in scope.
- `runtime_media` is not source truth and is not the final frontend representation.
- Backend read composition is the sole authority for frontend-facing governed media representation.
- The only canonical frontend-facing governed media representation is `media = { media_id, state, resolved_url } | null`.
- Governed media must follow one source-to-read authority chain only:
  - `media_id`
  - source inclusion or placement table
  - `runtime_media` where in scope
  - backend read composition
  - API
  - frontend
- `home_player_course_links` is source truth for course-linked home audio inclusion.
- Backend composition is read authority for course-linked home audio output.
- No direct write path may target `runtime_media`.
- No client-side media authority exists.
- Frontend is render-only for governed media and must not resolve, construct, infer, or normalize media truth.
- Storage-native paths, raw blob references, signed URLs, download URLs, preview URLs, playback URLs, and compatibility fallback payloads are not canonical media truth.
- Cross-domain media doctrine must not be redefined in domain or execution contracts.

## 4. Cross-Domain Determinism Law

- Cross-domain deterministic behavior must be defined once at the system-law layer unless it is strictly stage-specific.
- Equivalent canonical inputs must not produce alternate contract interpretations.
- Deterministic contract behavior may not depend on hidden fallbacks, shadow authority, or undocumented alternate paths.

## 5. No-Fallback And Stop Law

- If canonical authority is missing, conflicted, or unresolved, the contract workflow must stop.
- No contract may define fallback authority to compensate for missing canonical law.
- Missing, broken, or ambiguous authority pointers must be repaired explicitly rather than bypassed.
- When a rule cannot be placed in one canonical location, implementation must stop and report the blocker.

## 6. Separation Law

- Structure law, content law, media lifecycle law, public-surface law, and execution transport law must remain in separate canonical locations.
- Structure authority and content authority must remain distinct concerns.
- Editor write surfaces and learner read surfaces must remain distinct concerns.
- One path must exist for each concept or responsibility.
- Multiple paths for the same responsibility make the system invalid.
- No endpoint may mix structure and content responsibilities.
- Contextual presence of structure or content inside another canonical surface does not collapse distinct authorities.
- Read surfaces must not become semantic write authority, and write surfaces must not become semantic read authority.
- No contract may mix cross-domain system law with domain-owned law or execution-owned law.
- Execution projection does not own domain semantics.
- Domain semantics do not own system-law doctrine.

## 7. Execution-Boundary Law

- Execution contracts may contain only response shapes, transport behavior, ordering, nullability, and execution-surface constraints.
- Execution contracts must reference `SYSTEM_LAWS.md` and their owning domain contract.
- Execution contracts may not define field ownership, cross-domain doctrine, or fallback authority.
- Contracts under `actual_truth/contracts/retrieval/` are retrieval-stage contracts, not execution contracts.
- Retrieval-stage contracts are not subject to the execution response-shape-only rule.
