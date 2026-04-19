# AVELI EXECUTION POLICY

## PURPOSE

This file defines **what Codex must assume as already decided truth**
and therefore must NOT ask the user about.

It removes redundant decision loops while preserving strict determinism.

---

# CORE PRINCIPLE

Codex MUST behave as a deterministic operator.

Codex MUST:

- apply existing system laws automatically
- not re-ask resolved decisions
- not introduce alternative interpretations

Codex MUST STOP only when:

- canonical truth is missing
- dependency chain is incomplete
- system laws conflict

---

# GLOBAL RULE

If something is defined in:

- contracts/
- Aveli_System_Decisions.md
- aveli_system_manifest.json

Then:

→ it is NOT a question
→ it is an instruction

---

# MEDIA POLICY

Canonical media model:

runtime_media → backend_read_composition → resolved_url

Codex MUST assume:

- `resolved_url` is the ONLY valid playback representation
- frontend MUST NOT construct or resolve media
- backend is the ONLY authority for media representation

---

## FORBIDDEN (NO DISCUSSION)

- playback_url
- download_url
- signed_url
- signed_url_expires_at
- preferredUrl as fallback
- any secondary resolver path
- storage URL exposure as contract truth

---

## REQUIRED BEHAVIOR

Codex MUST:

- remove legacy media fields automatically
- remove fallback branches automatically
- update tests to match canonical media object
- reject invalid media paths instead of transforming them

---

# AUTH / PROFILE POLICY

Codex MUST assume:

- auth schema is canonical via Baseline V2 lock
- app.profiles must match active backend usage
- no partial schema allowed

Codex MUST NOT:

- guess auth structure
- ignore missing columns
- create temporary fallback columns

---

# ONBOARDING POLICY

Codex MUST assume:

- onboarding_state is canonical
- role, role_v2, is_admin are required fields
- onboarding logic must align with backend truth

Codex MUST NOT:

- invent onboarding defaults
- bypass role logic
- treat onboarding as optional if schema requires it

---

# DATABASE POLICY

Canonical DB authority:

backend/supabase/baseline_v2_slots
backend/supabase/baseline_v2_slots.lock.json

Codex MUST:

- treat Baseline V2 locked slots as truth
- align DB schema to Baseline V2 locked slots
- replay baseline when mismatch detected

Codex MUST NOT:

- patch DB ad hoc
- rely on existing DB state as truth
- mix migration sources

---

# TEST POLICY

Tests are:

- verification layer
- not source of truth

---

## REQUIRED

Codex MUST:

- update tests to match canonical contracts
- remove tests enforcing legacy behavior
- ensure tests validate actual system laws

---

## FORBIDDEN

Codex MUST NOT:

- modify domain logic to satisfy broken tests
- preserve legacy behavior because tests expect it
- skip failing tests silently

---

# MCP POLICY

MCP is:

validation layer, not execution authority

Codex MUST:

- use MCP to verify runtime truth
- not rely on MCP as primary data source
- ensure MCP aligns with canonical contracts

Codex MUST NOT:

- use MCP to justify incorrect system behavior
- keep legacy paths because MCP exposes them

---

# INDEX / RETRIEVAL POLICY

Codex MUST:

- use existing index
- use semantic + lexical retrieval
- use chunk-level reasoning
- identify hidden dependencies

Codex MUST NOT:

- rebuild index without explicit instruction
- rely on shallow grep only
- assume first result is complete

---

# EXECUTION POLICY

Codex MUST:

- execute ONE task at a time
- respect dependency graph
- stop on any ambiguity
- generate next task prompt, not auto-run

Codex MUST NOT:

- batch tasks
- skip STOP conditions
- expand scope implicitly
- fix unrelated issues “while here”

---

# AUTOMATIC DECISION RULES

Codex MUST automatically:

- remove legacy fields when found
- align code to canonical contracts
- eliminate fallback logic
- enforce single-path-per-concept
- update tests to canonical truth

Codex MUST NOT ask about these.

---

# STOP CONDITIONS (STRICT)

Codex MUST STOP if:

- canonical replacement does not exist
- dependency chain incomplete
- environment prevents verification
- schema authority unclear
- multiple conflicting truths detected

---

# NON-STOP CONDITIONS

Codex MUST CONTINUE if:

- issue is already defined by policy
- legacy behavior is clearly invalid
- tests are outdated but fixable
- code deviates from canonical contract

---

# EXECUTION PRIORITY MODEL

When conflict exists:

1. SYSTEM_LAWS
2. CURRENT_TRUTH
3. EMERGENT_TRUTH
4. TESTS
5. UI

---

# FINAL RULE

Codex is not allowed to:

- hesitate on resolved decisions
- ask redundant questions
- preserve legacy behavior

Codex is required to:

- enforce canonical truth
- eliminate ambiguity
- maintain determinism

---

END OF POLICY
