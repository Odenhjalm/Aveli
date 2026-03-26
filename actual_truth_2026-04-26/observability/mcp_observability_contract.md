# MCP Observability Contract

Source context loaded:
- `codex/AVELI_OPERATING_SYSTEM.md`
- `aveli_system_manifest.json`
- `.vscode/mcp.json`
- `backend/app/main.py`
- `backend/app/routes/logs_mcp.py`
- `backend/app/routes/media_control_plane_mcp.py`
- `backend/app/routes/verification_mcp.py`
- `backend/app/routes/domain_observability_mcp.py`
- `actual_truth_2026-04-26/DETERMINED_PLAN/VERIFIED_TASKS/*`

This contract defines the current repo-backed MCP execution surface that Codex can rely on during local task execution.

## 1. Mounted Local HTTP MCP Routes

The FastAPI app currently mounts four local-only MCP HTTP routes:

| MCP config key | GET route | POST route | JSON-RPC `serverInfo.name` | Responsibility |
| --- | --- | --- | --- | --- |
| `aveli_logs` | `/mcp/logs` | `/mcp/logs` | `aveli-logs-mcp` | recent backend errors, media failures, cleanup activity, worker health |
| `aveli_media_control_plane` | `/mcp/media-control-plane` | `/mcp/media-control-plane` | `aveli-media-control-plane-mcp` | asset snapshots, asset lifecycle traces, orphaned assets, runtime projection validation |
| `aveli_verification` | `/mcp/verification` | `/mcp/verification` | `aveli-verification-mcp` | high-level lesson/course verification verdicts and bounded test-case discovery |
| `aveli_domain_observability` | `/mcp/domain-observability` | `/mcp/domain-observability` | `aveli-domain-observability-mcp` | user-domain and media-domain inspection across existing read paths |

Repo note:
- `.vscode/mcp.json` also configures `aveli_semantic_search`.
- That server is a repo-side stdio helper, not a mounted FastAPI HTTP MCP route.
- It is not part of the backend runtime contract documented here.

## 2. Mounted Transport Contract

All four mounted MCP routes currently share these transport rules:

- `GET /mcp/<server>` returns a local-only availability response with:
  - `status`
  - `data`
  - `source`
  - `confidence`
- `POST /mcp/<server>` accepts JSON-RPC requests for:
  - `initialize`
  - `notifications/initialized`
  - `tools/list`
  - `tools/call`
- Local-only access is enforced by:
  - client host checks
  - `Origin` host checks
  - per-server `*_mcp_enabled` flags
- The fallback response header is `MCP-Protocol-Version: 2025-03-26`.
- `initialize` may negotiate `2025-11-25` when that protocol version is provided.

Current response envelope for successful `tools/call` results:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "status": "ok | error",
    "data": {},
    "source": {
      "server": "mounted-server-name",
      "timestamp": "ISO-8601 timestamp"
    },
    "confidence": "high | low"
  }
}
```

## 3. Current Server Roles

### `aveli_logs`

Use for deterministic runtime signals:
- `get_recent_errors`
- `get_media_failures`
- `get_cleanup_activity`
- `get_worker_health`

### `aveli_media_control_plane`

Use for canonical media-control truth:
- `get_asset`
- `trace_asset_lifecycle`
- `list_orphaned_assets`
- `validate_runtime_projection`

### `aveli_verification`

Use for bounded truth-verification verdicts:
- `verify_lesson_media_truth`
- `verify_course_cover_truth`
- `verify_phase2_truth_alignment`
- `get_test_cases`

### `aveli_domain_observability`

Use for cross-domain state inspection:
- `inspect_user`
- `inspect_media`

## 4. Current Usage Rules

- Prefer the mounted Aveli MCP routes before API, SQL, or UI when the task needs runtime or domain evidence.
- Use the highest-authority mounted route that directly answers the task:
  - route/runtime failures -> `aveli_logs`
  - media asset/runtime truth -> `aveli_media_control_plane`
  - bounded verification verdicts -> `aveli_verification`
  - cross-domain state inspection -> `aveli_domain_observability`
- Use repo documentation and task artifacts only after mounted MCP or repo contract evidence has been checked.
- The mounted MCP routes are read-only and must not be documented as mutation surfaces.

## 5. VERIFIED_TASK Execution Behavior

Current repo behavior is manual and task-scoped:

- VERIFIED_TASK files and operator instructions determine which pre-checks and post-checks must run.
- The backend does not implement a global automatic execution gate that blocks every mutation until all MCPs return `ok`.
- The mounted MCP routes provide evidence; they do not autonomously approve or deny task execution.

Current execution expectation:

- Pre-check only the mounted MCP surfaces relevant to the current task.
- Perform the scoped mutation.
- Re-run the same scoped checks after mutation.
- Stop if the relevant mounted MCP evidence contradicts the expected task outcome.

## 6. Example Contract Corrections

Current examples that should be treated as canonical:

- checkout creation:
  - `POST /api/checkout/create`
- lesson media upload lifecycle:
  - `POST /api/media/upload-url`
  - direct upload to the returned `upload_url`
  - `POST /api/media/complete`
  - `POST /api/media/attach`
- mounted MCP routes:
  - `GET/POST /mcp/logs`
  - `GET/POST /mcp/media-control-plane`
  - `GET/POST /mcp/verification`
  - `GET/POST /mcp/domain-observability`

Historical examples that are not part of this mounted execution contract:

- `POST /checkout/session`
- lesson-upload examples centered on `/studio/lessons/{lesson_id}/media/presign`
- docs-only claims that VERIFIED_TASK execution is automatically gated by MCP responses

## 7. Stop Conditions

Stop and re-check source truth if:

- mounted route code and docs disagree
- a required MCP route is not mounted in `backend/app/main.py`
- a contract claim requires inventing automatic behavior not implemented in route code
