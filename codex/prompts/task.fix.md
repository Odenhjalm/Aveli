# Uppgift (Bugfix)
Problem: {symptom/logg}
Filer: {berorda filer}

## MCP Bootstrap Pattern
- If this task involves MCP usage, backend verification, local backend testing
  involving backend runtime, or MCP-based audit, insert the exact block from
  `codex/prompts/MCP_BOOTSTRAP_BLOCK.md` here before any diagnosis, audit,
  verification, implementation, or testing instruction.
- For MCP/backend-dependent work, the block is mandatory and fail-closed under
  `codex/AVELI_OPERATING_SYSTEM.md`; do not mark it optional or skippable.

## Forvantat resultat
- ...

## Diagnos
- Kort analys, root cause (om kand).

## Ramar
- Starta alltid uppgiften med ny branch:
  `./codex/scripts/start-task-branch.sh "<task-name>"`

## Leverans
- ENDAST giltig unified diff som fixar buggen.
- Lagg till minimal reproducerbarhet/test dar mojligt.
