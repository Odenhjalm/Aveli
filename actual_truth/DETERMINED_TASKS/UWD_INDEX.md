| ID | short description | dependencies |
|---|---|---|
| UWD-001 | Establish a write-path isolation boundary for all active, shadow, and dead write routes in this scope without changing canonical authorities. | [] |
| UWD-002 | Add the canonical Course + Lesson Editor backend write surfaces while preserving isolated legacy paths during switchover. | [UWD-001] |
| UWD-003 | Add the canonical lesson-media backend write surfaces while preserving isolated legacy paths during switchover. | [UWD-001] |
| UWD-004 | Switch the studio course editor from mixed lesson writes to the canonical lesson structure/content split. | [UWD-002] |
| UWD-005 | Switch studio lesson-media upload callers from `/api/lesson-media/{lesson_id}/upload-url` plus implicit placement to the canonical upload-url, upload-completion, and placement-attach sequence. | [UWD-003] |
| UWD-006 | Remove the mounted mixed lesson write surfaces `POST /studio/lessons` and `PATCH /studio/lessons/{lesson_id}` after frontend switchover. | [UWD-004] |
| UWD-007 | Remove or unmount non-canonical mounted media write surfaces after frontend switchover. | [UWD-005] |
| UWD-008 | Quarantine or remove dead but dangerous write callers and helpers after active paths are replaced. | [UWD-006, UWD-007] |
| UWD-009 | Enforce canonical write-path invariants after removal. | [UWD-006, UWD-007, UWD-008] |
| UWD-010 | Remove frontend contract dependencies that only existed for legacy write/read paths. | [UWD-009] |
| UWD-011 | Rewrite backend Course + Lesson Editor tests to assert the canonical split. | [UWD-009] |
| UWD-012 | Rewrite backend and frontend media pipeline tests to assert the canonical three-step media write chain. | [UWD-009, UWD-010] |
| UWD-013 | Add dominance regression gates that fail if non-canonical write dominance returns. | [UWD-011, UWD-012] |
| UWD-014 | Clean up stale support artifacts only after test alignment passes. | [UWD-013] |
