# 0009E_media_contract_unification

TASK_ID: T005
STATUS: COMPLETE
TYPE: OWNER
PURPOSE: Ersätt learner/public lesson-media-kontraktet med kanonisk backend-authored media-payload så att frontend inte längre resolver media från `lesson_media_id`.
FILES AFFECTED:
- backend/app/schemas/__init__.py
- backend/app/repositories/courses.py
- backend/app/services/courses_service.py
- backend/app/routes/courses.py
- frontend/lib/features/courses/data/courses_repository.dart
- frontend/lib/features/courses/presentation/lesson_page.dart
- frontend/lib/shared/utils/lesson_media_playback_resolver.dart
DEPENDS_ON:
- none
DONE_WHEN:
- `LessonContentResponse.media` exponerar inte `preview_ready` eller `original_name` som learner-runtime-kontrakt.
- Learner/public media levereras som backend-authored `media = { media_id, state, resolved_url } | null`.
- Frontend renderar lesson media endast från backend-authored `media.resolved_url`.
- Ingen learner/public yta gör separat playback-upplösning från `lesson_media_id`.
VALIDATION:
- `rg "preview_ready|original_name" backend/app/schemas/__init__.py frontend/lib/features/courses` visar inga aktiva learner/public-kontraktsberoenden.
- `rg "resolveLessonMediaSignedPlaybackUrl|fetchLessonPlaybackUrl" frontend/lib/features/courses/presentation/lesson_page.dart frontend/lib/shared/utils/lesson_media_playback_resolver.dart` visar ingen aktiv learner/public-upplösning.
- Riktad backendverifiering av `GET /courses/lessons/{lesson_id}`-kontrakt använder backend-authored media-objekt.
