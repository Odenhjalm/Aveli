# Aveli Observatory Contract

## Purpose

The Aveli Observatory is the admin-only operations dashboard for platform health,
media diagnostics, payment integrity, data substrate status, deploy readiness,
verification workflows, and bounded log inspection.

This contract defines the intended page map, route ownership, and data source
priority for the observatory frontend.

## Route Map

- `/admin`
  - Overview page.
- `/admin/media`
  - Media observability page.
- `/admin/payments`
  - Payments observability page.
- `/admin/data`
  - Data observability page.
- `/admin/deploys`
  - Deploy observability page.
- `/admin/verification`
  - Verification page.
- `/admin/logs`
  - Logs page.
- `/admin/users`
  - Admin-only canonical teacher-role mutations.
- `/admin/settings`
  - Canonical admin settings and metrics.
- `/admin/media-control`
  - Legacy alias to the media observability page.

## Shell Contract

- Primary navigation owns:
  - `Overview`
  - `Media`
  - `Payments`
  - `Data`
  - `Deploys`
  - `Verification`
  - `Logs`
- Utility navigation owns:
  - `Users`
  - `System`
  - `Studio`
- The observatory shell is rendered inside `AppScaffold` with `useBasePage: false`
  and uses its own internal left navigation and glass-panel content area.

## Source Priority

### Stable admin HTTP sources

- `GET /admin/settings`
  - Canonical admin metrics, payment rollups, and teacher priorities.
- `GET /admin/media/health`
  - Canonical media control-plane health, access, capabilities, and shortcuts.

### Local observability MCP JSON-RPC sources

- `POST /mcp/dev-operator`
  - Cross-system operator summary and last failure.
- `POST /mcp/logs`
  - Recent errors, media failures, cleanup activity, worker health.
- `POST /mcp/media-control-plane`
  - Asset inspection, lifecycle tracing, orphaned assets, runtime projection validation.
- `POST /mcp/domain-observability`
  - User inspection and media-domain inspection.
- `POST /mcp/verification`
  - Phase alignment, lesson media truth, course cover truth, deterministic test cases.
- `POST /mcp/supabase-observability`
  - Connection health, auth alignment, domain projection health, storage health.
- `POST /mcp/stripe-observability`
  - Checkout, subscription, payment, webhook, reconciliation surfaces.
- `POST /mcp/netlify-observability`
  - Deploy, build, env, and connectivity readiness surfaces.

## Degradation Rules

- `/admin/settings` and `/admin/media/health` are the stable top-level sources and
  must continue to power the overview even when local MCP feeds are unavailable.
- MCP-backed observability pages are read-only and may degrade to unavailable when:
  - the backend MCP feature flag is disabled
  - the client is not local
  - the local-only origin restriction blocks the request
- Local MCP unavailability must not hide or replace canonical admin settings/media
  data; it only reduces drill-down depth.

## Interaction Contract

- Summary cards may either:
  - navigate to the owning page, or
  - open a read-only drill-down payload view
- Drill-down views are read-only and show structured payload evidence.
- Verification, data inspection, and media inspection accept explicit operator ids
  as inputs and must not invent identifiers.

## Security Contract

- All observatory routes are admin routes in the frontend route manifest.
- Final authority remains backend-enforced.
- Existing forbidden-session behavior must redirect admins away from observatory
  routes back to `/home` with a snackbar.

## Compatibility

- `/admin/media-control` remains supported as a legacy alias.
- `/admin/users` and `/admin/settings` remain live and continue to use the shared
  observatory shell rather than a separate admin layout.
