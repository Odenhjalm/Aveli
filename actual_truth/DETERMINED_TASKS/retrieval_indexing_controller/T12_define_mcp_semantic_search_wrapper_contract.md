# T12 - Define MCP Semantic Search Wrapper Contract

TYPE: design
OS_ROLE: OWNER
EXECUTION_STATUS: PASS
DEPENDS_ON: [T11]

## Purpose

Define how the semantic-search MCP server becomes a thin wrapper over canonical
read-only retrieval.

## Scope

Design only. Do not modify `tools/mcp/semantic_search_server.py` and do not run
MCP.

## Authority References

- `actual_truth/contracts/retrieval/retrieval_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- T11 read-only retrieval contract
- observed file: `tools/mcp/semantic_search_server.py`

## Dependencies

- T11

## Expected Outcome

The MCP wrapper contract defines that MCP validates JSON-RPC input only, calls
canonical retrieval, returns canonical evidence objects inside the JSON-RPC
response, owns no model/embedding/rerank/ranking/corpus/cache/artifact policy,
matches canonical retrieval output except for protocol envelope, and is
Windows-compatible.

## Stop Conditions

- MCP hardcodes a model.
- MCP embeds documents or queries independently.
- MCP reranks independently.
- MCP parses CLI text output instead of consuming canonical retrieval objects.
- MCP scans corpus or writes cache.
- MCP uses `/bin` interpreter paths.

## Verification Requirements

- For a fixed query fixture, MCP structured output matches canonical retrieval JSON byte-for-byte after removing JSON-RPC envelope.
- MCP failure messages are deterministic and Swedish where user-facing.
- No MCP path can trigger a rebuild.

## Mutation Rules

No runtime mutation is allowed during this design task. Controller execution may
update this task status and write `T12_execution_result.md` only.

## Output Artifacts

- `T12_execution_result.md`

## Next Transitions

- T13
