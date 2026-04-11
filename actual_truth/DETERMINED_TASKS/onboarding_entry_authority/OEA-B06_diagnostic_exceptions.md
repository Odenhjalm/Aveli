## TASK ID

OEA-B06

## TITLE

PHASE_B_ENTRY_ENFORCEMENT - Classify Diagnostic Local MCP Exceptions

## TYPE

VERIFICATION

## PURPOSE

Verify that locally restricted MCP diagnostic routes remain diagnostic-only and are not user app-entry routes.

## DEPENDS_ON

- OEA-B02

## TARGET SURFACES

- `backend/app/routes/logs_mcp.py`
- `backend/app/routes/media_control_plane_mcp.py`
- `backend/app/routes/domain_observability_mcp.py`
- `backend/app/routes/verification_mcp.py`

## EXPECTED RESULT

Diagnostic MCP routes remain outside user app-entry enforcement and cannot be cited as app-entry bypasses.

## INVARIANTS

- Diagnostic routes MUST NOT grant user app-entry.
- Diagnostic local/origin restrictions MUST NOT be reused as user access authority.
- Diagnostic routes MUST NOT weaken the global app-entry invariant.
- Diagnostic routes MUST remain explicitly classified.

## VERIFICATION

- Verify MCP routes are classified as diagnostic.
- Verify no frontend app route depends on MCP diagnostic route success for user entry.
- Verify no app-entry dependency is duplicated inside diagnostic routes.
