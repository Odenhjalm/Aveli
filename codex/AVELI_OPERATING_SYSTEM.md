# AVELI Operating System

## Purpose

This document is the standing operating contract for Codex inside Aveli.

Unless a future prompt explicitly overrides it, Codex MUST follow this document.
Future prompts may stay short because the default operating rules live here.

Codex operates as a deterministic system operator, not a guessing assistant.

The default operating loop is:

1. Bootstrap the environment and control planes.
2. Establish truth from authoritative sources.
3. Run a read-only baseline verification.
4. Apply the smallest safe mutation through the correct plane.
5. Re-verify the exact invariant that was changed.
6. Clean up temporary artifacts.
7. Report evidence, outcome, and residual risk.

Manual exploration is not verification. UI symptoms are not root truth.

## Local Anchors

These repo files define the local operating baseline:

- `.vscode/mcp.json` - registered MCP servers and endpoints
- `ops/env_load.sh` - canonical environment bootstrap
- `ops/env_validate.sh` - environment validation
- `ops/verify_all.sh` - full verification flow
- `ops/verify_all_minimal.sh` - minimal verification flow
- `supabase/migrations/` - canonical schema history
- `README.md` - repo-wide operational conventions

## Truth Hierarchy

When sources disagree, resolve truth in this order:

1. Versioned contracts in the repo
   This includes schema, code, environment loaders, migration history, and MCP configuration.
2. Aveli authoritative MCP read models
   This includes `aveli-domain-observability`, `aveli-media-control-plane`, and `aveli-verification`.
3. Direct backend API responses
   Use these for boundary behavior, auth enforcement, and public contract confirmation.
4. SQL reads of canonical storage state
   Use these for row-level proof, not as a substitute for domain-level interpretation when an MCP exists.
5. `aveli-logs`
   Logs explain execution and failure paths, but they do not define intended behavior.
6. Playwright and UI observation
   UI is the final symptom layer, not the first source of truth.

Rules:

- Prefer the highest authoritative layer that can answer the question.
- Do not skip directly to UI when a domain MCP can answer the same question.
- Do not use logs to overrule domain state or repo contracts.
- Do not use SQL to infer derived behavior if a domain-level MCP already exposes that behavior.

## MCP Stack And Purpose

### Primary Aveli Operator Stack

| MCP | Purpose | Default Use |
| --- | --- | --- |
| `aveli-domain-observability` | Domain state, lifecycle, invariants, runtime truth | Start here for runtime diagnosis and state confirmation |
| `aveli-logs` | Execution traces, correlation, exceptions, timings | Use after domain state is known to explain why something happened |
| `aveli-media-control-plane` | Canonical media identity, readiness, resolution, controlled media operations | Use for media diagnosis and media mutations |
| `aveli-verification` | Structured deterministic checks | Use before and after mutations; prefer over manual exploration |
| `playwright` | User-path and browser verification | Use last, only after lower layers are coherent |

### Supporting MCPs

| MCP | Purpose | Default Use |
| --- | --- | --- |
| `supabase` | Schema inspection, database tooling, branching, functions, docs | Use for schema truth, controlled DB work, and Supabase diagnostics |
| `context7` | External library documentation | Use for package and framework truth; never guess third-party APIs |
| `figma` | Design context and asset extraction | Use only for design-to-code work |

Rules:

- If Aveli exposes a capability through an Aveli MCP, prefer that MCP over ad hoc UI exploration.
- Supporting MCPs do not overrule Aveli runtime truth.
- Playwright is part of the stack, but it is not the primary operating plane.

## Runtime Bootstrap Order

For any task that touches runtime behavior, use this order:

1. Identify the target surface, environment, and invariant.
   Convert the task into: entity, action, expected result, actual result, and environment.
2. Load environment through `ops/env_load.sh`.
   Do not assemble env state by hand if the repo already defines the loader.
3. Validate environment through `ops/env_validate.sh`.
   Fail closed on missing or ambiguous environment state.
4. Read the relevant local contract.
   This usually means the relevant backend route/service, frontend surface, migration history, and `.vscode/mcp.json`.
5. Establish runtime truth with `aveli-domain-observability`.
   Determine the current domain state before looking at symptoms.
6. Attach the task-specific MCPs.
   Use `aveli-media-control-plane` for media tasks, `aveli-logs` for execution explanation, and `aveli-verification` for structured probes.
7. Run a read-only baseline verification.
   Capture evidence before any mutation.
8. Use API, SQL, or Playwright only as focused follow-up layers.
   Do not start at those layers unless the task is explicitly limited to them.

For code-only tasks without runtime interaction, still read the local contract first and keep the same truth hierarchy.

## Auth Handling Rules

Auth is part of system state and MUST be handled explicitly.

Rules:

- Confirm the target environment before making privileged calls.
- Use repo-managed env loading before trusting tokens or keys.
- Fail closed if auth is missing, stale, ambiguous, or points at the wrong environment.
- Use the lowest privilege that can answer the question.
- Prefer read-only access until the mutation plan is clear.
- Never print, persist, or copy secrets into docs, code, tests, or chat output.
- Never hardcode credentials, cookies, bearer tokens, or signed URLs.
- Never use UI login state as proof that backend auth is correct.
- If production access is required, read first and mutate only with explicit task justification.

 ## AUTH BOOTSTRAP (E2E VERIFICATION)

Default rule:
- Do not use /auth/login for normal operation
- Do not create or modify users for the purpose of testing

Exception:
- If E2E_EMAIL and E2E_PASSWORD are defined in environment
- Codex MAY call /auth/login using ONLY those credentials

Purpose:
- Establish a safe, isolated test session for UI and end-to-end verification
- Avoid modifying existing production users or data

Rules:

- E2E credentials are treated as controlled test identities
- They MUST NOT overlap with real user accounts
- They MUST NOT be modified
- They MUST NOT be used for anything except verification flows

Execution:

1. If E2E_EMAIL and E2E_PASSWORD exist:
   - Perform /auth/login
   - Store access token
   - Use it for:
     - API calls
     - Playwright session bootstrap

2. If E2E credentials do not exist:
   - STOP
   - Report missing auth bootstrap

3. Never attempt:
   - guessing credentials
   - scanning for users
   - using reset-password flows
   - creating users via API or DB

Outcome:

- Auth is deterministic
- No mutation of production data
- No exploratory login behavior

## Verification Order

Every runtime-affecting task follows this verification chain:

1. Contract verification
   Confirm the intended behavior in code, schema, config, or migration history.
2. State verification
   Confirm current domain state with `aveli-domain-observability` and other relevant Aveli MCPs.
3. Baseline verification
   Run `aveli-verification` or the closest deterministic probe before mutation.
4. Mutation
   Apply the smallest possible change through the authoritative plane.
5. Post-mutation verification
   Re-run the same probe that established the baseline.
6. Boundary verification
   Use API checks to confirm public contract behavior if relevant.
7. User-path verification
   Use Playwright only if the task requires user-visible confirmation.
8. Cleanup verification
   Confirm temporary artifacts, sessions, or test data are removed or isolated.

Rules:

- Verification must test the exact invariant that was changed.
- "I clicked around and it seemed fine" does not count as verification.
- If a deterministic verification step does not exist, Codex should state that gap explicitly and use the closest lower-risk substitute.

## Mutation Safety Rules

Codex MUST mutate conservatively.

Rules:

- No mutation without a pre-read.
- Use one authoritative mutation plane per step.
- Prefer MCP mutation surfaces over direct SQL or UI-driven mutation when available.
- Prefer API mutation over UI mutation when an authoritative API exists.
- Prefer SQL writes only for schema work, controlled data repair, or cases where no safer control plane exists.
- For schema changes, use versioned migrations under `supabase/migrations/`.
- For data repair, scope writes to explicit entity IDs and known invariants.
- Capture before and after evidence for every non-trivial mutation.
- Keep mutations idempotent or reversible when possible.
- Do not batch unrelated changes into one mutation.
- Do not mix diagnosis, repair, and cleanup in one unverified step.
- Do not mutate production-like environments just to explore.
- Do not use Playwright as a write plane unless the task is explicitly about a UI-only flow and no authoritative backend plane exists.

## Cleanup Policy

Cleanup is part of the task, not an optional extra.

Rules:

- Remove temporary files, local notes, scratch artifacts, and test outputs created during the session when they are not part of the requested deliverable.
- Close browser sessions and short-lived operator sessions when work is complete.
- Remove or isolate test data created for verification if that data is not intended to persist.
- Do not delete, revert, or modify user-created data unless the task explicitly requires it.
- Only clean up artifacts that Codex created or can prove are safe to remove.
- If cleanup cannot be completed safely, report the leftover artifacts precisely.

## Fallback Order

When the preferred plane cannot answer the question, fall back in this order:

1. Aveli authoritative MCP
2. Repo-defined local contract and verification scripts
3. Direct backend API
4. SQL read
5. SQL write or migration
6. Playwright UI verification
7. Human escalation

Rules:

- Move downward only when the higher layer is unavailable or insufficient.
- Record why the fallback was necessary.
- Never skip upward evidence gathering and jump straight to the UI.
- Never use a lower layer to contradict a higher layer without explaining the discrepancy.

## Domain-Level Observability Usage

`aveli-domain-observability` is the primary runtime diagnosis surface.

Default usage:

- Translate every bug report into domain terms before acting.
- Identify the domain entities involved.
- Identify the expected invariant.
- Identify the actual invariant.
- Identify the state transition or failure boundary.
- Use logs only after the domain state is known.

Rules:

- Prefer domain-state answers over transport-level noise.
- Use observability to establish "what state is the system actually in?"
- Use logs to establish "why did this transition or fail?"
- Use verification to establish "does the system now satisfy the intended invariant?"
- If domain observability and UI disagree, resolve the discrepancy before mutating.

## When To Use MCP vs SQL vs API vs UI

Use the smallest layer that is both authoritative and appropriate.

| Plane | Use When | Avoid When |
| --- | --- | --- |
| MCP | Aveli already exposes structured state, reason codes, verification, or controlled mutation | You only need raw storage proof or the MCP does not expose the needed capability |
| SQL read | You need canonical row-level data, schema truth, or drift confirmation | A domain MCP already gives the answer at the correct abstraction |
| SQL write / migration | You are changing schema, applying versioned DB changes, or doing tightly scoped data repair | An MCP or API can perform the mutation safely |
| API | You need to validate public/backend contract behavior, auth boundaries, or request/response semantics | The question is purely internal and already answered by MCP or SQL |
| UI / Playwright | You need end-user flow verification, browser behavior, rendering, or client orchestration proof | You are still establishing root truth or attempting backend mutation through the UI |

Decision rule:

- If the capability exists in an Aveli MCP, start there.
- If the question is about stored data shape, use SQL read.
- If the question is about external contract behavior, use API.
- If the question is about user-visible behavior after lower layers are verified, use UI.

## Standing Defaults For Future Tasks

Unless the prompt says otherwise, Codex SHOULD assume:

- Aveli MCPs are the default operating plane.
- Deterministic verification is required before and after meaningful mutations.
- UI verification is last, not first.
- Repo-defined env loading and validation are mandatory for runtime work.
- Domain observability outranks raw logs for diagnosis.
- Versioned migrations outrank ad hoc SQL for schema changes.
- Residual uncertainty must be stated explicitly, not hidden behind guesswork.

## PYTHON EXECUTION

Codex MUST use the repository’s Python toolchain.

Rules:

- NEVER call pytest directly
- NEVER assume system Python environment
- NEVER assume pytest is globally installed

Always use:

- poetry run <command>

Examples:

- Run tests:
  poetry run pytest path/to/test_file.py

- Run scripts:
  poetry run python script.py

- Start backend:
  poetry run uvicorn app.main:app

Detection:

- If pyproject.toml exists → use poetry
- Do not attempt alternative runners (pip, system python, uv) unless explicitly instructed

Failure handling:

- If poetry is missing → STOP
- Do not fallback to raw pytest or python