# courses — planned vs implemented

## planned sources
- `actual_truth_2026-04-24/Aveli_System_Decisions.md`
- `docs/README.md`
- `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md`
- `docs/audit/20260109_aveli_visdom_audit/SYSTEM_MAP.md`

## implemented sources
- `backend/app/routes/courses.py`
- `backend/app/repositories/courses.py`
- `backend/app/services/courses_service.py`
- `backend/app/services/course_bundles_service.py`
- `frontend/lib/features/courses/data/course_access_api.dart`
- `frontend/lib/features/courses/data/courses_repository.dart`
- `frontend/lib/features/courses/data/progress_repository.dart`
- `frontend/lib/features/courses/presentation/course_catalog_page.dart`
- `frontend/lib/features/courses/presentation/course_page.dart`
- `frontend/lib/features/courses/presentation/lesson_page.dart`
- `frontend/lib/features/courses/presentation/course_intro_page.dart`
- `frontend/lib/features/studio/data/studio_repository.dart`

## system should be
- Course docs should describe the runtime course/module/lesson shape that the app currently serves.
- Quiz-route audit conclusions should match the current frontend and backend method usage.

## system is
- `backend/app/routes/courses.py` now uses a `_virtual_module()` compatibility shim because modules are no longer stored as first-class rows.
- Frontend course pages use the current `/courses`, `/courses/{course_id}/modules`, and lesson-detail surfaces successfully against that shim.
- The older audit baseline still records a PATCH quiz-question mismatch even though the current frontend `studio_repository.dart` and backend `studio.py` both use PUT for question updates.

## mismatches
- `[important] courses_resolve_virtual_module_contract` — runtime course structure is now virtual-module-based, while docs and imports still imply persisted modules as primary structure.
- `[informational] courses_refresh_quiz_route_audit` — the old quiz PATCH mismatch is stale relative to current frontend/backend code.
