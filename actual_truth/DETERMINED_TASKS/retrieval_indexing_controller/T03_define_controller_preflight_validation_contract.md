# T03 - Define Controller Preflight Validation Contract

TYPE: design
OS_ROLE: OWNER
EXECUTION_STATUS: NOT_STARTED
DEPENDS_ON: [T02]

## Purpose

Define the fail-closed preflight contract that must run before any retrieval,
build, embedding, storage, or MCP search operation.

## Scope

Design preflight checks only. Do not run environment setup, install
dependencies, download models, or create `.repo_index`.

## Authority References

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- T02 manifest schema

## Dependencies

- T02

## Expected Outcome

Preflight validates explicit task and mode, Windows interpreter
`.repo_index/.search_venv/Scripts/python.exe`, dependency availability from the
locked interpreter only, local model availability without download, no CUDA
requirement, no `/bin` path, no bash-only path, no AF_UNIX, no `pgrep`,
manifest schema validity, artifact presence and hash binding for retrieval, and
approval state for build requests.

## Stop Conditions

- Required interpreter is missing.
- Any dependency requires system Python, `.venv`, or shell activation.
- Model availability would require network download.
- CUDA is required for correctness.
- A query request detects missing/corrupt index artifacts.
- Preflight attempts auto-repair.

## Verification Requirements

- Each failure reports the exact missing or invalid prerequisite in Swedish.
- Preflight exits before any artifact write, model load, or query operation.
- Preflight does not infer alternative interpreters or devices.

## Mutation Rules

No mutation is allowed during this design task.

## Output Artifacts

Future execution may produce a preflight contract result document.

## Next Transitions

- T04
- T08
- T13
- T14
