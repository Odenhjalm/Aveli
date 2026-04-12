# MCP BOOTSTRAP BLOCK (MANDATORY)

Authority: `codex/AVELI_OPERATING_SYSTEM.md` -> `MCP Bootstrap Law`.

This block is REQUIRED before any audit, verification, implementation, or
testing step when the task involves MCP usage, backend verification, local
backend testing involving backend runtime, or MCP-based audits.

1. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ops/mcp_bootstrap_gate.ps1
```

2. If the gate does not return `MCP_BOOTSTRAP_GATE_OK`, STOP.
3. Report the failing checks clearly.
4. Do not proceed into MCP-backed audits, backend verification, local backend
   testing, implementation, or verification while the gate is failing.
5. If the gate returns `MCP_BOOTSTRAP_GATE_OK`, report `MCP_BOOTSTRAP: PASS`
   and continue with the task-scoped workflow.
