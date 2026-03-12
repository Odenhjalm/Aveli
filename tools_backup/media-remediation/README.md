# Media Remediation Pipeline

This package implements a no-delete media remediation pipeline for production use.

Pipeline order:

1. Read-only inventory
2. Media issue classification
3. Repair execution
4. Post-repair verification
5. Safety report

Safety guarantees:

- No deletion is performed anywhere in this package.
- All real course/lesson media rows are in repair scope, including unpublished courses and draft lessons.
- Repair execution is dry-run by default.
- Repair actions run object-first, then reference-first.
- Legacy `lesson_media.media_asset_id` backfills only occur when a single verified `READY` asset match exists.
- FFmpeg is only required for local transcode repairs and is preflighted before non-dry-run transcode execution.

## SQL Views

- [`supabase/migrations/20260312110000_active_media_inventory_view.sql`](/home/rodenhjalm/Aveli/supabase/migrations/20260312110000_active_media_inventory_view.sql)
- [`supabase/migrations/20260312110100_media_repair_plan_view.sql`](/home/rodenhjalm/Aveli/supabase/migrations/20260312110100_media_repair_plan_view.sql)

## Environment

Required:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

Optional:

- `MEDIA_REMEDIATION_DRY_RUN=true|false`
- `MEDIA_REMEDIATION_ACTIVE_ONLY=true|false` (legacy compatibility flag; inventory scope now covers all real lesson media rows)
- `MEDIA_REMEDIATION_OUTPUT_DIR=reports/media-remediation`
- `MEDIA_REMEDIATION_MIN_BYTE_SIZE=100`
- `MEDIA_REMEDIATION_FFMPEG=ffmpeg`

## Commands

From [`tools/media-remediation`](/home/rodenhjalm/Aveli/tools/media-remediation):

```bash
npm install
npm run typecheck
npm run build
node ./dist/src/run-media-remediation.js --dry-run
```

Target a single course batch:

```bash
node ./dist/src/run-media-remediation.js --dry-run --course-id <course-uuid>
```

Standalone phase entrypoints:

- `node ./dist/src/repair-executor.js --dry-run`
- `node ./dist/src/post-repair-verifier.js`
- `node ./dist/src/safety-report.js`

Constrain standalone repair execution to one strategy:

```bash
node ./dist/src/repair-executor.js --course-id <course-uuid> --fix-strategy BACKFILL_MEDIA_ASSET
```

## Outputs

Each run creates a timestamped directory under `reports/media-remediation/` with:

- `01-active-media-inventory.json|md`
- `02-media-repair-plan.json|md`
- `03-planned-repair-manifest.json`
- `03-executed-repair-manifest.json`
- `04-post-repair-verification.json|md`
- `05-safety-report.json|md`
- `pipeline-summary.json`
- `audit.log`

The safety report groups candidates into:

- `SAFE_TO_QUARANTINE`
- `NEEDS_MANUAL_REVIEW`
- `BLOCKED_BY_ACTIVE_REFERENCE`
