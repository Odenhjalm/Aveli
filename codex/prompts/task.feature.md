# Uppgift (Feature)
Beskrivning: {kort beskrivning av featuren}

## MCP Bootstrap Pattern
- If this task involves MCP usage, backend verification, local backend testing
  involving backend runtime, or MCP-based audit, insert the exact block from
  `codex/prompts/MCP_BOOTSTRAP_BLOCK.md` here before any audit, verification,
  implementation, or testing instruction.
- For MCP/backend-dependent work, the block is mandatory and fail-closed under
  `codex/AVELI_OPERATING_SYSTEM.md`; do not mark it optional or skippable.

## Acceptanskriterier
- [ ] ...

## Ramar
- Folj `AGENT_PROMPT.md` (stack, RLS, betalfloden).
- Skapa migrations/edge functions om det kravs.
- Lagg till provdata/seeds dar det hjalper utveckling/test.
- Starta alltid uppgiften med ny branch:
  `./codex/scripts/start-task-branch.sh "<task-name>"`

## Leverans
- ENDAST giltig unified diff (git apply -p0).
- Uppdatera/skapade filer ska vara korbara.
- Inkludera kommandoexempel i PR-beskrivning (om PR).
