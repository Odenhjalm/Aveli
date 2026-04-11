## TASK ID

OEA-B05

## TITLE

PHASE_B_ENTRY_ENFORCEMENT - Preserve Course Access Separation After Entry

## TYPE

BACKEND_ALIGNMENT

## PURPOSE

Preserve the separation between global app-entry and protected course access while migrating route enforcement.

## DEPENDS_ON

- OEA-B03

## TARGET SURFACES

- `backend/app/routes/courses.py`
- `backend/app/services/courses_service.py`
- `backend/app/repositories/courses.py`
- `backend/app/repositories/course_enrollments.py`
- `backend/supabase/baseline_slots/0003_course_enrollments_core.sql`

## EXPECTED RESULT

Protected lesson/content access requires canonical app-entry and canonical course enrollment where the route is protected. Course enrollment never grants global app-entry.

## INVARIANTS

- `app.course_enrollments` MUST govern protected course access.
- `app.course_enrollments` MUST NEVER grant global app-entry.
- Membership MUST NEVER grant protected lesson/content access by itself.
- Intro course selection MUST NOT be a hard global app-entry gate.

## VERIFICATION

- Verify app-entry without course enrollment cannot access protected lessons.
- Verify course enrollment without active membership and completed onboarding cannot enter global app routes.
- Verify public course discovery remains public.
