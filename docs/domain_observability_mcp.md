# Domain Observability MCP Server

Read-only local MCP surface for deterministic domain inspection.

## Route Contract

- `GET /mcp/domain-observability`
- `POST /mcp/domain-observability`
- Default local target: `http://127.0.0.1:8080/mcp/domain-observability`
- Access is restricted to local clients and local `Origin` headers.

## Current Mounted Tool Surface

Only these tools are currently mounted:

- `inspect_user(user_id)`
- `inspect_media(asset_id | lesson_id)`

Anything else is out of scope for the current mounted contract and must not be
documented as active runtime truth.

## Positioning

- `logs_mcp` answers infrastructure and recent-failure questions.
- `media_control_plane_mcp` answers asset/runtime/media projection questions.
- `verification_mcp` answers alignment questions between local candidate state
  and expected truth.
- `domain_observability_mcp` answers bounded domain questions for user and media
  inspection.

## Safety Rules

- Read-only only: no inserts, updates, deletes, sync calls, or storage writes.
- No signed URLs, secrets, cookies, or tokens in responses.
- Local-only access enforcement matches the other mounted backend MCP routes.
- Output must stay deterministic and bounded.

## Tool Summary

### `inspect_user(user_id)`

Returns a deterministic user-domain snapshot using existing read paths for:

- auth user presence and verification state
- profile presence and role state
- membership state
- stored vs derived onboarding state
- authored and enrolled course ids
- course entitlement slugs

If the inspected user is missing locally, the tool should still return a
structured JSON response with a `missing` or `warning`/`error` status instead of
failing with a schema-level exception.

### `inspect_media(asset_id | lesson_id)`

Returns a deterministic media-domain snapshot using existing read paths for:

- media asset state
- lesson-media references
- runtime projection state
- relevant logs-derived failures
- bounded worker-health context

Exactly one of `asset_id` or `lesson_id` must be supplied.

## JSON-RPC Notes

- `initialize` is supported.
- `tools/list` returns only the mounted tools above.
- `tools/call` dispatches to the mounted tools above.

## Repo Guidance

- `.vscode/mcp.json` is the explicit local connector map for repo-side MCP
  access.
- Generic MCP registry visibility outside the mounted backend routes is not an
  authoritative source of this server's tool surface and must not be treated as
  one.
- When repo guidance and mounted route behavior disagree, the mounted route
  behavior is the runtime contract to document.
