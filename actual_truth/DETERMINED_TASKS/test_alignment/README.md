# TEST_ALIGNMENT TASK TREE

## SECTION: TASK TREE

### 1. COURSE_MODEL_REWRITE

- `TA-001` -> delete intro-only legacy endpoint/action tests
- `TA-002` -> rewrite remaining course-model tests to canonical Newbaseline fields and endpoints
- `TA-003` -> validate the rewritten course-model cluster

### 2. ACCESS_MODEL_REWRITE

- `TA-004` -> delete duplicate-authority and step-ownership legacy tests
- `TA-005` -> rewrite access-model tests to explicit `course.step` + `course_enrollments.source` rules
- `TA-006` -> validate the rewritten access-model cluster

### 3. MEDIA_SYSTEM_FIX

- `TA-007` -> implement runtime-media, lesson-media, and asset-authority fixes
- `TA-008` -> validate the media-system cluster against canonical runtime-media truth

### 4. ROUTE_FIX

- `TA-011` -> implement route wiring and mounted-surface fixes after auth/core route truth is stabilized
- `TA-012` -> validate the route-mismatch cluster

### 5. AUTH_FIX

- `TA-009` -> implement auth/email flow fixes
- `TA-010` -> validate the auth cluster

### AGGREGATE

- `TA-013` -> aggregate cluster-completion validation
- `TA-014` -> rerun the full test-to-Newbaseline diff after all cluster tasks complete

## DEPENDENCY SUMMARY

- Roots: `TA-001`, `TA-007`, `TA-009`
- Course rewrite must complete before access rewrite starts.
- Media fixes are independent of legacy course/access rewrites.
- Route fixes depend on auth/core route truth from `TA-009`.
- Aggregate tasks execute last.

## MATERIALIZED TASK FILES

- [TA-001_course_model_delete_legacy_surfaces.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/TA-001_course_model_delete_legacy_surfaces.md)
- [TA-002_course_model_rewrite.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/TA-002_course_model_rewrite.md)
- [TA-003_course_model_gate.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/TA-003_course_model_gate.md)
- [TA-004_access_model_delete_legacy_authority_tests.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/TA-004_access_model_delete_legacy_authority_tests.md)
- [TA-005_access_model_rewrite.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/TA-005_access_model_rewrite.md)
- [TA-006_access_model_gate.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/TA-006_access_model_gate.md)
- [TA-007_media_system_fix.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/TA-007_media_system_fix.md)
- [TA-008_media_system_gate.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/TA-008_media_system_gate.md)
- [TA-009_auth_fix.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/TA-009_auth_fix.md)
- [TA-010_auth_gate.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/TA-010_auth_gate.md)
- [TA-011_route_fix.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/TA-011_route_fix.md)
- [TA-012_route_gate.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/TA-012_route_gate.md)
- [TA-013_alignment_aggregate.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/TA-013_alignment_aggregate.md)
- [TA-014_full_diff_rerun_aggregate.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/TA-014_full_diff_rerun_aggregate.md)
- [task_manifest.json](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/test_alignment/task_manifest.json)
