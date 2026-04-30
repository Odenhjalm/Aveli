# HOME ENTRY VIEW CONTRACT

STATUS: ACTIVE

This contract defines the canonical backend read surface for authenticated Home
entry-view ongoing courses.

It operates under:

- `SYSTEM_LAWS.md`
- `AVELI_COURSE_DOMAIN_SPEC.md`
- `course_public_surface_contract.md`
- `supabase_integration_boundary_contract.md`

This contract does not redefine course access, lesson progression, governed
media, Supabase boundary, or frontend render-only law. It defines the Home
entry-view composition that consumes those authorities.

## 1. CANONICAL SURFACE

Endpoint:

```text
GET /home/entry-view
```

Owner:

- backend Home read composition

Consumer:

- authenticated Home UI

Purpose:

- provide a backend-authored list of ongoing courses for Home
- allow Home to render ongoing courses without frontend-derived progression,
  ranking, next lesson, or CTA/action logic

Maximum result count:

- `ongoing_courses` MUST contain at most 2 items

## 2. NON-AUTHORITIES

The following MUST NOT determine Home ongoing-course identity, ranking,
progression, next lesson, CTA, or action:

- `GET /courses/me`
- frontend profile slicing or limiting
- frontend Home course showcase data
- frontend CTA fallback logic
- Supabase client, storage, auth metadata, storage paths, or storage URLs

## 3. ALLOWED PRIMITIVE INPUTS

Backend Home read composition MAY consume only canonical backend-owned course
and media authorities:

- `app.course_enrollments` for protected course-content access and unlock state
- `app.courses` for course identity and required enrollment source
- `app.lessons` or canonical lesson structure read projection for lesson order
  and lesson identity
- `app.lesson_completions` for actual lesson completion state
- backend governed-media read composition for course cover media

All Supabase substrate access remains subject to
`supabase_integration_boundary_contract.md`.

## 4. RESPONSE CONTRACT

Response shape:

```json
{
  "ongoing_courses": [
    {
      "course_id": "uuid",
      "slug": "string",
      "title": "string",
      "cover_media": {
        "media_id": "uuid|null",
        "state": "string",
        "resolved_url": "string|null"
      },
      "progress": {
        "state": "not_started|in_progress",
        "completed_lesson_count": 0,
        "total_lesson_count": 0,
        "available_lesson_count": 0,
        "percent": 0.0,
        "last_activity_at": "timestamp|null"
      },
      "next_lesson": {
        "id": "uuid",
        "lesson_title": "string",
        "position": 1
      },
      "cta": {
        "type": "continue|unavailable",
        "label": "string",
        "enabled": true,
        "action": { "type": "lesson", "lesson_id": "uuid" },
        "reason_code": "string|null",
        "reason_text": "string|null"
      },
      "status": {
        "eligibility": "ongoing",
        "reason_code": "string|null"
      }
    }
  ]
}
```

Field rules:

- `ongoing_courses` MUST be present and MUST be an array.
- `course_id`, `slug`, and `title` MUST come from backend course authority.
- `cover_media` MUST use backend governed-media read composition and MUST NOT
  expose storage-native paths or frontend-resolved URLs.
- `progress.percent` MUST be backend-authored, deterministic, and derived from
  `completed_lesson_count / total_lesson_count` when `total_lesson_count > 0`.
- `next_lesson` MUST be backend-selected under this contract's next lesson rule.
- `cta` MUST be backend-authored and MUST contain either an explicit action or a
  null action with a backend reason.
- `status` is diagnostic backend status only and MUST NOT become frontend
  decision authority.

## 5. ELIGIBILITY RULE

A course is eligible for `ongoing_courses` only when all are true:

- the request has an authenticated app user
- the user has valid protected course access under course-domain authority
- the enrollment source is valid for the course's required enrollment source
- the course is learner-renderable under canonical backend read composition
- the course has at least one lesson
- the course is not fully completed
- at least one unlocked incomplete lesson exists

If any condition cannot be evaluated from canonical backend authority, the
course MUST NOT be emitted. If the authority itself is missing or conflicted,
implementation MUST stop.

## 6. COMPLETION AWARENESS

Completion state MUST come from `app.lesson_completions`.

Backend Home read composition MUST NOT:

- mark an unlocked lesson as completed unless a canonical completion row exists
- infer completion from `current_unlock_position`
- infer completion from frontend state
- infer completion from playback, navigation, profile, or Home UI state

`completed_lesson_count` MUST count canonical completed lessons for the course
and user. `total_lesson_count` MUST count canonical lessons in the course.

## 7. NEXT LESSON RULE

Backend MUST select `next_lesson` as follows:

1. Build the course lesson set from canonical lesson structure authority.
2. Sort lessons by `position ASC, id ASC`.
3. Build the completed lesson set from canonical lesson completion authority.
4. Treat a lesson as available only when course access is valid and
   `lesson.position <= app.course_enrollments.current_unlock_position`.
5. Select the first available lesson that has no canonical completion row.

Locked, drip-unavailable, inaccessible, or already-completed lessons MUST NOT be
selected as `next_lesson`.

If no next lesson can be selected, the course MUST NOT be emitted as ongoing.

## 8. RANKING RULE

Backend MUST rank eligible ongoing courses deterministically before applying the
maximum result count.

Sort keys:

1. `activity_sort_at DESC`, where `activity_sort_at` is the latest canonical
   lesson completion timestamp when present, otherwise enrollment `granted_at`.
2. `next_lesson.position ASC`.
3. `completed_lesson_count DESC`.
4. course progression-group position ASC when available.
5. `course_id ASC`.

Frontend MUST NOT sort, slice, rank, or repair `ongoing_courses`.

## 9. CTA RULE

For an emitted ongoing course with a selectable next lesson, backend MUST emit:

```json
{
  "type": "continue",
  "enabled": true,
  "action": { "type": "lesson", "lesson_id": "uuid" }
}
```

The `action.lesson_id` MUST equal `next_lesson.id`.

If backend cannot produce a valid explicit action, it MUST either omit the
course or emit:

```json
{
  "type": "unavailable",
  "enabled": false,
  "action": null
}
```

with backend-authored `reason_code` and `reason_text`.

Frontend MUST NOT reconstruct navigation from `next_lesson`, course slug,
lesson order, or any fallback branch.

## 10. EMPTY STATE RULE

When no eligible ongoing courses exist, backend MUST return:

```json
{
  "ongoing_courses": []
}
```

The authenticated Home UI MUST render no ongoing-course strip when
`ongoing_courses` is empty.

## 11. FORBIDDEN FRONTEND BEHAVIOR

Frontend MUST NOT:

- call `GET /courses/me` to derive Home ongoing courses
- reuse Profile "ongoing courses" slicing for Home
- use course showcase or popular course data as ongoing-course authority
- compute progression, completion, availability, lock state, next lesson,
  ranking, or CTA/action
- navigate by fallback when `cta.action` is null or missing
- resolve, construct, normalize, or repair media URLs
- use Supabase client, storage, or auth metadata as course-entry authority

## 12. STOP CONDITIONS

Implementation MUST stop if any are true:

- this contract is absent from `actual_truth/contracts/`
- `GET /home/entry-view` is not listed as an allowed learner read surface
- valid enrollment/access cannot be evaluated through backend authority
- lesson completion state cannot be read from canonical completion authority
- next lesson selection would require frontend fallback
- deterministic ranking cannot be produced from canonical backend fields
- CTA action cannot be authored explicitly by backend
- media output would require frontend URL construction or storage fallback
- implementation would change frontend Home behavior before backend read-model
  authority exists
