# INTRO COURSE SELECTION AND PROGRESSION CONTRACT

## STATUS

ACTIVE

This contract defines the canonical intro-course selection, progression, and
access model.

This contract operates under `SYSTEM_LAWS.md`.

This contract composes with:

- `course_access_contract.md`
- `course_drip_schedule_contract.md`
- `commerce_membership_contract.md`
- `onboarding_entry_authority_contract.md`

This contract owns only intro-course selection and progression law, and it
composes existing intro-course access law without redefining its underlying
owners.

This contract does not own:

- app-entry authority
- membership current-state authority
- protected course-access authority
- drip schedule computation
- lesson-completion storage or transport authority

## 1. PURPOSE

This contract is the single authoritative location for intro-course selection
and progression behavior, and the canonical composition point for intro-course
access behavior.

It defines the canonical rules for:

- intro course selection
- intro course progression
- intro course access
- the relationship between intro-course behavior, membership, enrollment, and
  drip systems

This contract exists to eliminate ambiguity between:

- selection
  - the ability to choose and enroll in a new intro course
- access
  - the ability to consume a course that already has a valid enrollment

## 2. SYSTEM POSITIONING

- Membership in `app.memberships` controls app access only.
- Course access is controlled only by `app.course_enrollments`.
- Intro-course logic does not override or bypass membership authority,
  app-entry authority, or course-access authority.
- Intro-course logic is a progression and selection layer on top of existing
  systems.
- Selection state is never app-entry authority.
- Selection state is never course-access authority.
- Selection state is never purchase or payment authority.

## 3. INTRO COURSE CLASSIFICATION

- A course is an intro course if and only if
  `app.courses.required_enrollment_source = 'intro'`.
- An intro enrollment is a canonical `app.course_enrollments` row for a course
  classified as an intro course, with enrollment source
  `intro` under the existing access law.
- Intro-course classification is owned only by
  `app.courses.required_enrollment_source`.
- Publish-time course classification MUST persist
  `app.courses.required_enrollment_source = 'intro'` for
  `app.courses.group_position = 0`.
- Runtime intro-course selection uses the persisted
  `app.courses.required_enrollment_source`, which must match the publish-time
  group-position authority.
- The structural intro slot of a course family is not course-access authority
  unless publish has persisted `required_enrollment_source = 'intro'`.

The following are forbidden as intro-course classification authority:

- price-based inference
- frontend-only `group_position` inference without persisted backend classification
- frontend flags
- naming inference
- tagging inference

## 4. ACCESS MODEL (NON-NEGOTIABLE)

- A user may consume an intro course if and only if both are true:
  - the user has valid membership and app entry is allowed
  - a valid `app.course_enrollments` row exists for that course
- Course access remains owned by `course_access_contract.md`.
- App entry remains owned by `onboarding_entry_authority_contract.md` and
  `commerce_membership_contract.md`.
- All intro courses with existing enrollments remain accessible under the
  unchanged validity rules of `course_access_contract.md`.
- There is no canonical concept of an "inactive course" that changes access.
- Past intro courses remain consumable after later intro selections, later
  intro progression, or later selection-lock changes.
- Selection state, drip state, course-family order, and enrollment recency
  must not deactivate an already valid intro-course enrollment.
- This contract introduces no new access-revocation path.

## 5. SELECTION MODEL (SEPARATE FROM ACCESS)

- Selection determines only whether a user is allowed to enroll in a new intro
  course.
- Selection never changes access to an already enrolled intro course.
- Selection is evaluated across the user's intro enrollments only.
- A user may select a new intro course only if there is no intro enrollment
  whose drip progression is incomplete.

For this contract, "incomplete drip" means:

- `app.course_enrollments.current_unlock_position < max(app.lessons.position)`
  for that enrolled intro course

## 6. PROGRESSION MODEL

- Intro-course progression is determined by:
  - drip release through `app.course_enrollments.current_unlock_position`
  - lesson completion through canonical backend lesson-completion authority
- `course_drip_schedule_contract.md` remains the only owner of unlock-position
  computation and drip advancement.
- This contract consumes unlock state; it does not define how unlock state is
  computed.
- This contract consumes canonical lesson-completion state; it does not define
  the lesson-completion storage model or mutation surface.
- Eligibility for the next intro course requires both:
  - the final lesson has been unlocked
  - all lessons in the progressed intro course are completed
- For next-course eligibility, "final lesson has been unlocked" means
  `current_unlock_position = max(app.lessons.position)` for the intro
  enrollment being evaluated.
- Full unlock without full completion does not satisfy next-course eligibility.
- The final lesson may auto-complete after a separately defined backend time
  window, for example 7 days.
- Once that auto-completion is canonically applied by backend authority, it
  counts as completed for intro-course progression.

## 7. SINGLE-PROGRESSION INVARIANT

- At most one intro enrollment may exist in a drip-incomplete state at any
  time for one user.
- Backend enforcement of this invariant is mandatory.
- Creating a second drip-incomplete intro enrollment while another one exists
  is forbidden.
- UI behavior, operational convention, or manual data interpretation must not
  replace backend enforcement of this invariant.

## 8. SELECTION LOCK BEHAVIOR

- If a drip-incomplete intro enrollment exists, all intro-course selection
  actions must be denied.
- If no drip-incomplete intro enrollment exists, all intro courses that are
  otherwise eligible under this contract become selectable.
- Selection lock affects only enrollment actions that would create a new intro
  enrollment.
- Selection lock does not affect course access.
- Selection lock does not revoke, suspend, hide, or deactivate previously
  enrolled intro courses.

## 9. UI/CLIENT IMPLICATIONS (NON-AUTHORITATIVE)

- UI may disable `Anmäl dig` buttons when selection is locked.
- UI may display locked or unlocked selection state only as a projection of
  backend authority.
- UI must not enforce intro-course selection rules independently.
- UI must rely on backend responses for allow or deny outcomes.

## 10. FORBIDDEN BEHAVIORS

- using enrollment recency (`enrolled_at`) as an implicit "active course"
- deleting enrollments to enforce single-course behavior
- denying access to previously enrolled intro courses
- deriving intro-course behavior from non-canonical fields
- introducing frontend-only selection logic
- treating selection lock as access revocation
- treating drip incompleteness as access revocation

## 11. RELATION TO EXISTING CONTRACTS

- `course_access_contract.md` continues to own protected course-access truth,
  access classification matching, and access revocation.
- `course_drip_schedule_contract.md` continues to own drip mode resolution,
  enrollment initialization, and `current_unlock_position` advancement.
- `commerce_membership_contract.md` continues to own membership current-state
  truth.
- `onboarding_entry_authority_contract.md` continues to own global app-entry
  authority and post-auth entry composition.
- This contract extends those contracts by defining intro-course selection and
  intro-course progression on top of their existing authority.
- This contract does not override, bypass, or replace their authority.

## 12. CANONICAL SUMMARY

- Enrollment = access
- Drip + completion = progression
- Selection = gated by progression
- Selection does NOT control access
