Development rules:

1. Always read Figma MCP before generating UI code.
2. Always use Context7 MCP for external libraries.
3. Always inspect Supabase schema before writing SQL.
4. After implementing UI features, run Playwright tests.
5. Never guess APIs when Context7 is available.

Workflow standard:

Phase A Plan
- Inspect Figma
- Inspect DB schema
- Fetch library docs

Phase B Implement
- Implement code
- Generate tests

Phase C Integrate
- Connect the feature to the existing app flow
- Reconcile dependencies, routing, and data contracts

Phase D Verify
- Run Playwright tests after UI work
- Run the best practical local verification before handoff

## Editor Observability

The editor includes a built-in observability layer:

- EditorDebugOverlay (UI)
- logEditor() tracing
- controller/session/revision tracking

Agents must:

- use this system before debugging
- rely on runtime logs instead of guessing
- never debug editor behavior without enabling kEditorDebug

Before exploring the repository, read the repo index in .repo_index.

Use:
files.txt → locate files
tags → locate functions
tree.txt → understand structure

Before searching the repository manually, always run semantic code search:

tools/index/semantic_search.sh "<query>"

Use the results to identify relevant files before reading code.
