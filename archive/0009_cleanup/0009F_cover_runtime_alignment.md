# 0009F_cover_runtime_alignment

TASK_ID: T006
STATUS: COMPLETE
TYPE: OWNER
PURPOSE: Flytta course-cover-read-modellen från direkt `media_assets`-bypass till kanonisk runtime-baserad read composition utan cover-specifik resolver.
FILES AFFECTED:
- backend/app/services/courses_service.py
- backend/app/services/courses_read_service.py
- backend/app/repositories/runtime_media.py
- frontend/lib/shared/utils/course_cover_resolver.dart
- frontend/lib/features/courses/presentation/course_page.dart
- frontend/lib/features/courses/presentation/course_catalog_page.dart
- frontend/lib/shared/widgets/courses_grid.dart
- frontend/lib/shared/widgets/courses_showcase_section.dart
DEPENDS_ON:
- T005
DONE_WHEN:
- Ingen learner/public cover-yta signer eller resolver cover från `cover_media_id`.
- Backend cover-read composition använder runtime-baserad truth eller fail-closed när runtime-truth saknas.
- Ingen aktiv course-cover-read-path läser `streaming_object_path` direkt från `media_assets` som frontendtruth.
VALIDATION:
- `rg "signMedia\\(|resolveCourseCoverUrl" frontend/lib/features/courses frontend/lib/shared/widgets frontend/lib/shared/utils/course_cover_resolver.dart` visar ingen aktiv learner/public cover-resolution från frontend.
- `rg "streaming_object_path" backend/app/services/courses_service.py` visar ingen cover-read-bypass.
- Riktad verifiering av course detail/list-kontrakt visar endast backend-authored `cover = { media_id, state, resolved_url } | null`.
