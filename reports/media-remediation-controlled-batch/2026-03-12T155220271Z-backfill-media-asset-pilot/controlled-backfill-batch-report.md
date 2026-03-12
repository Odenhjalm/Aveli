# BACKFILL_MEDIA_ASSET Controlled Batch Pilot

Generated at: 2026-03-12T15:56:49.121Z

- apply: true
- batch_size_limit: 5
- selected_rows: 5
- executed_sql_mutations: 5
- aborted: false
- abort_reason: none

## Rows Selected

| repair_priority | course_id | lesson_id | lesson_media_id | safe_matching_media_asset_id | preflight_probe |
| --- | --- | --- | --- | --- | --- |
| 25 | 15c7cab0-c5b8-41af-b3af-ef732c645106 | eb87712f-d590-40d7-940d-d06fc48c2636 | e2a17c71-e42c-4fa2-842b-30c08d918759 | e6306de3-0598-4850-9159-782c9103def0 | PASS |
| 25 | 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 999fa13c-4824-430e-8d04-1b47ffbd6a6f | 402f1201-14fb-48fb-9b99-1c3d59b9c7bd | PASS |
| 25 | 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 28a965f0-02fd-4253-a0fe-877a7b8d2fb2 | 402f1201-14fb-48fb-9b99-1c3d59b9c7bd | PASS |
| 25 | 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 7740905a-60f6-45c0-a92d-31a228793300 | 402f1201-14fb-48fb-9b99-1c3d59b9c7bd | PASS |
| 25 | 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 204a2227-4b98-4e3c-973d-3607286fac74 | 402f1201-14fb-48fb-9b99-1c3d59b9c7bd | PASS |

## Exact SQL Mutations Executed

```sql
update app.lesson_media set media_asset_id = 'e6306de3-0598-4850-9159-782c9103def0' where id = 'e2a17c71-e42c-4fa2-842b-30c08d918759' and media_asset_id is null;
update app.lesson_media set media_asset_id = '402f1201-14fb-48fb-9b99-1c3d59b9c7bd' where id = '999fa13c-4824-430e-8d04-1b47ffbd6a6f' and media_asset_id is null;
update app.lesson_media set media_asset_id = '402f1201-14fb-48fb-9b99-1c3d59b9c7bd' where id = '28a965f0-02fd-4253-a0fe-877a7b8d2fb2' and media_asset_id is null;
update app.lesson_media set media_asset_id = '402f1201-14fb-48fb-9b99-1c3d59b9c7bd' where id = '7740905a-60f6-45c0-a92d-31a228793300' and media_asset_id is null;
update app.lesson_media set media_asset_id = '402f1201-14fb-48fb-9b99-1c3d59b9c7bd' where id = '204a2227-4b98-4e3c-973d-3607286fac74' and media_asset_id is null;
```

## Verification Results Per Row

| status | course_id | lesson_id | lesson_media_id | message |
| --- | --- | --- | --- | --- |
| PASS | 15c7cab0-c5b8-41af-b3af-ef732c645106 | eb87712f-d590-40d7-940d-d06fc48c2636 | e2a17c71-e42c-4fa2-842b-30c08d918759 | verification checks passed |
| PASS | 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 999fa13c-4824-430e-8d04-1b47ffbd6a6f | verification checks passed |
| PASS | 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 28a965f0-02fd-4253-a0fe-877a7b8d2fb2 | verification checks passed |
| PASS | 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 7740905a-60f6-45c0-a92d-31a228793300 | verification checks passed |
| PASS | 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 204a2227-4b98-4e3c-973d-3607286fac74 | verification checks passed |

## Updated Inventory Snapshot For Affected Lessons

| course_id | lesson_id | lesson_media_id | reference_type | media_asset_id | media_asset_type | bucket | storage_path | content_type |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 15c7cab0-c5b8-41af-b3af-ef732c645106 | eb87712f-d590-40d7-940d-d06fc48c2636 | 6392bbb8-3b34-486a-8ae5-c41c1059bada | media_object |  |  | public-media | lessons/eb87712f-d590-40d7-940d-d06fc48c2636/images/8fa4ded6-b18c-445b-a3e3-4657feaf57a9.png | image/png |
| 15c7cab0-c5b8-41af-b3af-ef732c645106 | eb87712f-d590-40d7-940d-d06fc48c2636 | 9d21729d-59c6-41cb-97d7-86add9c043f9 | media_asset | e6306de3-0598-4850-9159-782c9103def0 | audio | course-media | media/derived/audio/courses/15c7cab0-c5b8-41af-b3af-ef732c645106/lessons/eb87712f-d590-40d7-940d-d06fc48c2636/56b3959f92d04f349b018c76c7ed3697_intuitiv-healing-ngla.mp3 | audio/mpeg |
| 15c7cab0-c5b8-41af-b3af-ef732c645106 | eb87712f-d590-40d7-940d-d06fc48c2636 | e2a17c71-e42c-4fa2-842b-30c08d918759 | media_asset | e6306de3-0598-4850-9159-782c9103def0 | audio | course-media | media/derived/audio/courses/15c7cab0-c5b8-41af-b3af-ef732c645106/lessons/eb87712f-d590-40d7-940d-d06fc48c2636/56b3959f92d04f349b018c76c7ed3697_intuitiv-healing-ngla.mp3 | audio/mpeg |
| 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 1b19f8cf-d2ae-4846-92a0-f81661b12860 | media_object |  |  | course-media | 31b70b33-9ce6-4595-8491-a1f99719fed1/4bf61669-fe1c-4aa5-b089-7638f0362839/image/8f245690d6d94c46974f09e20d89b735.png | image/png |
| 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 70b7c565-5e47-424f-9660-112f4b7f65fc | media_object |  |  | public-media | 31b70b33-9ce6-4595-8491-a1f99719fed1/4bf61669-fe1c-4aa5-b089-7638f0362839/image/359df251116542379b09cb6c29b68662.png | image/png |
| 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 2967de14-04f9-419d-9c6b-76866348ad72 | media_asset | 402f1201-14fb-48fb-9b99-1c3d59b9c7bd | audio | course-media | media/derived/audio/courses/31b70b33-9ce6-4595-8491-a1f99719fed1/lessons/4bf61669-fe1c-4aa5-b089-7638f0362839/2c4926392b664f74b337642a6fb0c29b_lekt vind 4.mp3 | audio/mpeg |
| 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 7c431a7b-6a49-4671-908c-9c63bfa5ae2c | media_object |  |  | public-media | 31b70b33-9ce6-4595-8491-a1f99719fed1/4bf61669-fe1c-4aa5-b089-7638f0362839/image/7a7ce44dc923477bbec916ae156b2142.png | image/png |
| 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | ffb4716a-bb29-4c08-b147-03b65f8d9ad2 | media_object |  |  | public-media | lessons/4bf61669-fe1c-4aa5-b089-7638f0362839/images/44e67fc9-32b1-4195-9e91-e8df9a72f3c2.png | image/png |
| 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | ff1d780d-d53c-4fe4-a134-cb5c6208861c | media_asset | cbfd02f5-488a-49d5-88b9-6bddec6aea93 | audio | course-media | media/source/audio/courses/31b70b33-9ce6-4595-8491-a1f99719fed1/lessons/4bf61669-fe1c-4aa5-b089-7638f0362839/89510f3836714263acaae1de6832c78f_övning vind.wav | audio/wav |
| 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 999fa13c-4824-430e-8d04-1b47ffbd6a6f | media_asset | 402f1201-14fb-48fb-9b99-1c3d59b9c7bd | audio | course-media | media/derived/audio/courses/31b70b33-9ce6-4595-8491-a1f99719fed1/lessons/4bf61669-fe1c-4aa5-b089-7638f0362839/2c4926392b664f74b337642a6fb0c29b_lekt vind 4.mp3 | audio/mpeg |
| 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 28a965f0-02fd-4253-a0fe-877a7b8d2fb2 | media_asset | 402f1201-14fb-48fb-9b99-1c3d59b9c7bd | audio | course-media | media/derived/audio/courses/31b70b33-9ce6-4595-8491-a1f99719fed1/lessons/4bf61669-fe1c-4aa5-b089-7638f0362839/2c4926392b664f74b337642a6fb0c29b_lekt vind 4.mp3 | audio/mpeg |
| 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 7740905a-60f6-45c0-a92d-31a228793300 | media_asset | 402f1201-14fb-48fb-9b99-1c3d59b9c7bd | audio | course-media | media/derived/audio/courses/31b70b33-9ce6-4595-8491-a1f99719fed1/lessons/4bf61669-fe1c-4aa5-b089-7638f0362839/2c4926392b664f74b337642a6fb0c29b_lekt vind 4.mp3 | audio/mpeg |
| 31b70b33-9ce6-4595-8491-a1f99719fed1 | 4bf61669-fe1c-4aa5-b089-7638f0362839 | 204a2227-4b98-4e3c-973d-3607286fac74 | media_asset | 402f1201-14fb-48fb-9b99-1c3d59b9c7bd | audio | course-media | media/derived/audio/courses/31b70b33-9ce6-4595-8491-a1f99719fed1/lessons/4bf61669-fe1c-4aa5-b089-7638f0362839/2c4926392b664f74b337642a6fb0c29b_lekt vind 4.mp3 | audio/mpeg |

## Remaining BACKFILL_MEDIA_ASSET Candidates

| repair_priority | course_id | lesson_id | lesson_media_id | safe_matching_media_asset_id | safe_matching_media_asset_count |
| --- | --- | --- | --- | --- | --- |
| 25 | 835cb790-c971-4401-9b0f-b3bcf0358b8e | c836a652-b36c-4677-8f74-97fae6657520 | 5d929e29-b380-4db4-8762-6fa1eb0595cc | 6d7ea1c3-4c9b-4fc9-b3b2-533a84a9f8c3 | 1 |
| 25 | 835cb790-c971-4401-9b0f-b3bcf0358b8e | c836a652-b36c-4677-8f74-97fae6657520 | 48da35b8-daf2-483f-b051-bbabb161466a | 6d7ea1c3-4c9b-4fc9-b3b2-533a84a9f8c3 | 1 |
| 25 | 835cb790-c971-4401-9b0f-b3bcf0358b8e | c836a652-b36c-4677-8f74-97fae6657520 | 241e0565-a30f-48e7-aa2b-6ff150aa22dd | 6d7ea1c3-4c9b-4fc9-b3b2-533a84a9f8c3 | 1 |
| 25 | 835cb790-c971-4401-9b0f-b3bcf0358b8e | c836a652-b36c-4677-8f74-97fae6657520 | 272ec874-57df-430d-a5fb-2f6c464c7a45 | 6d7ea1c3-4c9b-4fc9-b3b2-533a84a9f8c3 | 1 |
