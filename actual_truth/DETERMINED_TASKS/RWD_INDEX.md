| ID | short description | dependencies |
|---|---|---|
| RWD-001 | Add canonical backend placement reorder/delete surfaces under `media_pipeline_router`. | [] |
| RWD-004 | Align lesson delete to remove lesson-owned content, placement, and lesson rows without asset/runtime mutation. | [] |
| RWD-007 | Restore positive backend `cover_media_id` write persistence coverage. | [] |
| RWD-002 | Switch studio frontend reorder/delete callers to canonical placement endpoints. | [RWD-001] |
| RWD-003 | Remove or quarantine non-canonical mounted `/api/lesson-media` reorder/delete writes. | [RWD-002] |
| RWD-005 | Add non-deleting lifecycle trigger integration after placement link removal. | [RWD-001, RWD-003, RWD-004] |
| RWD-006 | Add canonical placement reorder/delete backend and frontend tests. | [RWD-005] |
| RWD-008 | Replace lesson-delete media cleanup coverage with placement-cleanup coverage. | [RWD-004, RWD-005] |
| RWD-009 | Restore course-cover lifecycle safety coverage under `media_lifecycle_contract.md`. | [RWD-005] |
| RWD-010 | Update dominance gates to forbid old reorder/delete surfaces. | [RWD-003, RWD-006] |
| RWD-011 | Perform the final no-code post-remediation audit gate. | [RWD-007, RWD-008, RWD-009, RWD-010] |
