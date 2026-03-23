# AVELI Operating System

## Purpose

This document defines the deterministic operating contract for Codex inside Aveli.

Codex operates as a system operator, not an assistant.

No guessing.
No improvisation.
No ambiguity.

---

## Core Loop

1. Bootstrap environment
2. Establish truth
3. Run baseline verification
4. Apply minimal mutation
5. Re-verify invariant
6. Cleanup
7. Report evidence

UI is not truth. Logs are not truth. Only verified state is truth.

---

## Truth Hierarchy

1. Repo contracts (code, schema, config)
2. Aveli MCPs
3. Backend API
4. SQL (read)
5. Logs
6. Playwright (verification only)

---

## MCP Stack

Primary:

- aveli-domain-observability → state truth
- aveli-verification → invariant checks
- aveli-media-control-plane → media truth
- aveli-logs → execution explanation
- playwright → UI verification

Supporting:

- supabase → schema + SQL
- context7 → external docs
- figma → design

---

## Runtime Defaults (MANDATORY)

Unless explicitly overridden:

- Backend: http://127.0.0.1:8080
- Frontend: http://127.0.0.1:3000
- MCP_MODE: local
- Worker: enabled

Do NOT resolve environment dynamically.
Do NOT use .env conflicts.

---

## Bootstrap Order

1. Load env (ops/env_load.sh)
2. Validate env (ops/env_validate.sh)
3. Confirm backend:
   - /healthz = 200
   - /readyz = 200
4. Confirm MCP endpoints:
   - /mcp/logs
   - /mcp/media-control-plane
   - /mcp/domain-observability
   - /mcp/verification
5. Confirm frontend:
   - http://127.0.0.1:3000 returns HTML

If any step fails → STOP

---

## Auth Model (E2E ONLY)

- ONLY allowed login: /auth/login using E2E_EMAIL + E2E_PASSWORD
- NEVER create users
- NEVER guess credentials
- NEVER use reset flows

After login:

- Use access token for API
- Inject tokens into browser storage for Playwright

If auth fails → STOP

---

## Verification Order

1. Contract
2. Domain state (MCP)
3. Verification MCP
4. Mutation
5. Re-verification
6. API boundary
7. UI (Playwright)
8. Cleanup verification

---

## Mutation Rules

- No mutation without pre-read
- One mutation plane per step
- Prefer MCP → API → SQL (last)
- No production data mutation
- Only test entities allowed

---

## Cleanup Rules

Codex MUST:

- Delete all created courses
- Delete all created media
- Clear all cover attachments
- Verify deletion via MCP + SQL

If cleanup incomplete → STOP and report

---

## Frontend Runtime (VERIFICATION)

Frontend MUST:

- Run at http://127.0.0.1:3000
- Use API_BASE_URL=http://127.0.0.1:8080
- Be a STATIC BUILD

Flutter dev server is NOT allowed.

---

## Static Frontend Execution

Build:

flutter build web --release -o /tmp/aveli-web \
  --dart-define=API_BASE_URL=http://127.0.0.1:8080 \
  --dart-define=FRONTEND_URL=http://127.0.0.1:3000

Serve (SPA REQUIRED):

python3 - <<'PY'
import http.server
from pathlib import Path

root = Path('/tmp/aveli-web').resolve()
index = root / 'index.html'

class SPAHandler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        path = path.split('?',1)[0].split('#',1)[0]
        resolved = (root / path.lstrip('/')).resolve()
        if not resolved.exists():
            return str(index)
        return str(resolved)

    def log_message(self, format, *args):
        return

http.server.ThreadingHTTPServer(('127.0.0.1', 3000), SPAHandler).serve_forever()
PY

---

## Playwright Rules

Playwright is a verification layer.

Allowed:

- UI rendering validation
- network verification
- user flow verification

Forbidden:

- auth workarounds
- token bridges
- local auth servers
- guessing routes

Auth MUST come from API login.

If UI requires hacks → STOP

---

## Playwright Auth Injection

Codex MUST:

- login via API
- inject tokens into browser storage
- reload app
- proceed

---

## Routing Requirement

Frontend MUST support SPA routing.

If routes fail → STOP

---

## Fallback Order

1. MCP
2. Repo scripts
3. API
4. SQL read
5. SQL write (rare)
6. UI
7. Human

---

## Final Rule

If ANY layer:

- diverges from DB truth
- overrides canonical identity
- fails cleanup

→ system is NOT verified

No exceptions.