# Media Robustness Report (Example)

- Total records: `3`

## By Category

- `legacy_lesson_media`: `2`
- `pipeline_media_asset`: `1`

## By Status

- `missing_bytes`: `1`
- `needs_migration`: `1`
- `ok`: `1`

## By Recommended Action

- `auto_migrate`: `1`
- `keep`: `1`
- `reupload_required`: `1`

## Records

| category | status | action | editor | student | lesson_media_id | media_id | kind | bucket | path |
|---|---|---|---|---|---|---|---|---|---|
| legacy_lesson_media | needs_migration | auto_migrate | ✅ | ✅ | 11111111-1111-1111-1111-111111111111 | aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa | image | course-media | lessons/lesson-123/demo.png |
| legacy_lesson_media | missing_bytes | reupload_required | ❌ | ❌ | 22222222-2222-2222-2222-222222222222 |  | video | course-media | lessons/lesson-456/missing.mp4 |
| pipeline_media_asset | ok | keep | ✅ | ✅ | 33333333-3333-3333-3333-333333333333 | bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb | audio | course-media | lessons/lesson-789/derived.mp3 |

## Notes

- Dry-run output is deterministic (no timestamps).
- No deletes are performed by this tool.

