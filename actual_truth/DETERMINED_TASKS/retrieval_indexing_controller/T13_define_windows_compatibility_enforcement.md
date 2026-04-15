# T13 - Define Windows Compatibility Enforcement

TYPE: design
OS_ROLE: GATE
EXECUTION_STATUS: PASS
DEPENDS_ON: [T03, T08, T11, T12]

## Purpose

Define the Windows-first compatibility gate for every retrieval/indexing
controller path.

## Scope

Design only. Do not modify shell scripts, Python files, or environment setup.

## Authority References

- `codex/AVELI_OPERATING_SYSTEM.md`
- T03 preflight contract
- T08 model policy
- T11 read-only retrieval contract
- T12 MCP wrapper contract
- observed current surfaces: `tools/index/*.sh`, `tools/index/search_code.py`, `tools/mcp/semantic_search_server.py`

## Dependencies

- T03
- T08
- T11
- T12

## Expected Outcome

The compatibility gate requires interpreter
`.repo_index/.search_venv/Scripts/python.exe`, no bare `python`, no shell
activation, no bash-only execution path, no `/bin` interpreter path, no AF_UNIX
socket dependency, no `pgrep`, no CUDA-only dependency for canonical
correctness, and no dynamic interpreter discovery when canonical interpreter is
known.

## Stop Conditions

- Any controller-required path is Unix-only.
- Any controller-required path depends on bash.
- Any retrieval/MCP path depends on AF_UNIX or `pgrep`.
- Any canonical path requires CUDA.
- Any script uses system Python or `.venv` for retrieval/indexing.

## Verification Requirements

- Static scan detects forbidden constructs before execution.
- Runtime preflight stops on forbidden interpreter or shell dependency.
- Windows interpreter path is the only permitted retrieval/indexing interpreter.

## Mutation Rules

No runtime mutation is allowed during this design task. Controller execution may
update this task status and write `T13_execution_result.md` only.

## Output Artifacts

- `T13_execution_result.md`

## Next Transitions

- T14
