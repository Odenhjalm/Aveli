# Domain Observability MCP Server

Read-only MCP layer for domain-level Aveli system introspection.

This layer sits above the existing low-level observability surfaces and returns
domain answers directly, so Codex does not need to manually correlate
`logs`, `media-control-plane`, course rows, lesson markdown, and editor
contract behavior.

## Route

- `POST /mcp/domain-observability`
- `GET /mcp/domain-observability`
- Local-only access, same JSON-RPC shape as the existing MCP routes
- Default local MCP target: `http://127.0.0.1:8080/mcp/domain-observability`
- Disabled by default in cloud runtimes via `domain_observability_mcp_enabled`

## Positioning

The layer is domain-oriented, not infrastructure-oriented.

- `logs_mcp` answers: "What failed recently?"
- `media_control_plane_mcp` answers: "What is the exact asset/runtime truth?"
- `verification_mcp` answers: "Do these truths align?"
- `domain_observability_mcp` answers: "What is the state of this user, media set,
  editor contract, lesson markdown, or course?"

## Safety

- Read-only only: no inserts, updates, deletes, trigger calls, sync calls, or
  storage writes
- No runtime side effects:
  - use repository reads only
  - use resolver inspection paths with `emit_logs=False`
  - do not call sync helpers such as runtime projection repair or home-player
    projection sync
- Local-only access and local `Origin` enforcement, same as existing MCP routes
- Bounded reads:
  - `inspect_user(user_id)`: authored/enrolled course lists capped at `25`
  - `inspect_media(...)`: inherits caps from control-plane and logs tools
  - `inspect_editor_state(course_id)`: lessons capped at `50`
  - `validate_content_markdown(lesson_id)`: single lesson only
  - `inspect_course(course_id)`: lessons capped at `50`
- Sensitive output is minimized:
  - no tokens, cookies, signed URLs, or raw secrets
  - no raw email addresses; only presence/match state
  - no authoritative write advice or mutation handles

## Design Rules

- Reuse existing truth sources instead of re-encoding business logic.
- Keep upstream services authoritative:
  - auth/profile/membership truth stays in repositories and onboarding service
  - media/runtime truth stays in media-control-plane observability and resolver
  - course cover truth stays in `courses_service.resolve_course_cover(...)`
  - lesson markdown write-contract truth stays in
    `courses_service.canonicalize_lesson_content(...)` and
    `app.utils.lesson_content`
- The MCP layer only:
  - orchestrates existing read paths
  - normalizes results
  - lifts inconsistencies into explicit domain findings
- The MCP layer is never authoritative for writes or state transitions.

## Current-System Constraint

`inspect_editor_state(course_id)` must describe persisted editor-contract state,
not ephemeral browser-local session state.

Today the backend owns:

- canonical lesson markdown
- lesson media rows
- canonical markdown normalization rules

Today the backend does not own:

- in-browser unsaved buffers
- cursor/focus/selection state
- active client session identity

So this tool should answer:

- can the stored lessons load into the Studio editor contract?
- are they canonical or only normalizable?
- which lessons are save-unsafe or legacy-shaped?

It should not pretend to answer:

- what a current browser tab has typed but not saved
- what the user's live cursor/selection is

## Common Output Contract

Every tool returns deterministic JSON with the same top-level shape:

```json
{
  "generated_at": "ISO-8601 timestamp",
  "inspection": {
    "tool": "stable_tool_name",
    "version": "1"
  },
  "subject": {},
  "status": "ok | warning | error | missing",
  "violations": [
    {
      "code": "stable_code",
      "message": "human-readable explanation",
      "severity": "error | warning | info",
      "source": "upstream_truth_source",
      "subject": {},
      "details": {}
    }
  ],
  "inconsistencies": [
    {
      "code": "stable_code",
      "message": "human-readable explanation",
      "source": "upstream_truth_source",
      "details": {}
    }
  ],
  "state_summary": {},
  "truth_sources": {},
  "sources_consulted": ["stable source names"]
}
```

### Status Rules

- `missing`: primary subject not found
- `error`: at least one `severity == "error"` violation
- `warning`: no error violations, at least one warning
- `ok`: no warning/error violations

### Determinism Rules

- sort violations by severity, code, then subject ids
- sort ids and counts lexicographically
- never include signed URLs or non-deterministic request ids
- use fixed enum strings for state summaries and violation codes

## Service Structure

### Route

- `backend/app/routes/domain_observability_mcp.py`
- Handles:
  - tool registration
  - local-only access control
  - deterministic JSON serialization
  - JSON-RPC protocol behavior identical to the other MCP routes

### Orchestration Package

- `backend/app/services/domain_observability/`

Suggested structure:

- `backend/app/services/domain_observability/__init__.py`
- `backend/app/services/domain_observability/common.py`
- `backend/app/services/domain_observability/user_inspection.py`
- `backend/app/services/domain_observability/media_inspection.py`
- `backend/app/services/domain_observability/editor_inspection.py`
- `backend/app/services/domain_observability/markdown_validation.py`
- `backend/app/services/domain_observability/course_inspection.py`

Common helpers should own:

- timestamp helpers
- deterministic sorting
- status derivation
- violation/inconsistency normalization
- bounded-scan helpers

### Shared Logic Extraction

To avoid duplicating markdown validation logic between scripts and MCP, extract
the reusable scanner from:

- `backend/scripts/scan_markdown_integrity.py`

into a shared read-only utility such as:

- `backend/app/utils/markdown_integrity.py`

The script and MCP service should both import that shared function.

Also promote read-only markdown reference extractors from
`backend/app/utils/lesson_content.py` as public helpers if needed, rather than
copying the regex logic into the MCP layer.

## Truth Sources Reused

### User/Auth

- `backend/app/repositories/auth.py`
  - `get_user_by_id(user_id)`
- `backend/app/repositories/profiles.py`
  - `get_profile(user_id)`
- `backend/app/repositories/memberships.py`
  - `get_membership(user_id)`
- `backend/app/services/onboarding_state.py`
  - `derive_onboarding_state(user_id)`
- `backend/app/repositories/courses.py`
  - `list_courses(teacher_id=...)`
  - `list_my_courses(user_id)`
- `backend/app/repositories/course_entitlements.py`
  - `list_entitlements_for_user(user_id)`

### Media

- `backend/app/services/media_control_plane_observability.py`
  - `get_asset(asset_id)`
  - `trace_asset_lifecycle(asset_id)`
  - `validate_runtime_projection(lesson_id)`
- `backend/app/services/logs_observability.py`
  - `get_media_failures(asset_id)`
  - `get_worker_health()`

### Course/Content

- `backend/app/services/courses_service.py`
  - `fetch_course(course_id=...)`
  - `list_course_lessons(course_id)`
  - `fetch_lesson(lesson_id)`
  - `resolve_course_cover(course_id, cover_media_id, cover_url)`
  - `canonicalize_lesson_content(markdown, lesson_id)`
- `backend/app/repositories/courses.py`
  - `list_lesson_media(lesson_id)`
  - `list_modules(course_id)`
  - `list_lessons(module_id)`
- `backend/app/utils/lesson_content.py`
  - `build_lesson_media_write_contract(...)`
  - `normalize_lesson_markdown_for_storage(...)`
  - `markdown_contains_legacy_document_media_links(...)`

## Tool Contracts

### `inspect_user(user_id)`

Purpose:

- Return one deterministic user-domain snapshot covering auth, profile,
  onboarding, membership, authored courses, enrolled courses, and entitlements.

Input:

```json
{
  "user_id": "uuid"
}
```

Returns:

```json
{
  "subject": {
    "user_id": "uuid"
  },
  "status": "ok | warning | error | missing",
  "violations": [],
  "inconsistencies": [],
  "state_summary": {
    "auth_user_state": "present | missing",
    "email_verification_state": "verified | unverified | missing",
    "profile_state": "present | missing",
    "profile_completeness": "complete | incomplete | unknown",
    "role_state": "user | teacher | admin | missing",
    "membership_state": "active | inactive | missing",
    "stored_onboarding_state": "string | null",
    "derived_onboarding_state": "string | null",
    "onboarding_alignment": "aligned | drift | unavailable",
    "authored_course_count": 0,
    "enrolled_course_count": 0,
    "entitlement_count": 0
  },
  "truth_sources": {
    "auth": {},
    "profile": {},
    "membership": {},
    "onboarding": {},
    "courses": {},
    "entitlements": {}
  }
}
```

Stable violations:

- `user_missing`
- `profile_missing`
- `profile_auth_email_mismatch`
- `onboarding_state_drift`

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "inspection": {
    "tool": "inspect_user",
    "version": "1"
  },
  "subject": {
    "user_id": "user-123"
  },
  "status": "warning",
  "violations": [
    {
      "code": "onboarding_state_drift",
      "message": "Stored onboarding state does not match the derived onboarding state",
      "severity": "warning",
      "source": "onboarding_state.derive_onboarding_state",
      "subject": {
        "user_id": "user-123"
      },
      "details": {
        "stored": "registered_unverified",
        "derived": "access_active_profile_complete"
      }
    }
  ],
  "inconsistencies": [
    {
      "code": "onboarding_state_drift",
      "message": "Stored onboarding state differs from derived state",
      "source": "onboarding_state.derive_onboarding_state",
      "details": {
        "stored": "registered_unverified",
        "derived": "access_active_profile_complete"
      }
    }
  ],
  "state_summary": {
    "auth_user_state": "present",
    "email_verification_state": "verified",
    "profile_state": "present",
    "profile_completeness": "complete",
    "role_state": "teacher",
    "membership_state": "inactive",
    "stored_onboarding_state": "registered_unverified",
    "derived_onboarding_state": "access_active_profile_complete",
    "onboarding_alignment": "drift",
    "authored_course_count": 3,
    "enrolled_course_count": 0,
    "entitlement_count": 1
  },
  "truth_sources": {
    "auth": {
      "user_present": true
    },
    "profile": {
      "profile_present": true
    },
    "membership": {
      "membership_present": false
    },
    "onboarding": {
      "stored": "registered_unverified",
      "derived": "access_active_profile_complete"
    },
    "courses": {
      "authored_course_ids": ["course-a", "course-b", "course-c"],
      "enrolled_course_ids": []
    },
    "entitlements": {
      "course_slugs": ["foundations-step1"]
    }
  },
  "sources_consulted": [
    "auth.get_user_by_id",
    "profiles.get_profile",
    "memberships.get_membership",
    "onboarding_state.derive_onboarding_state",
    "courses.list_courses",
    "courses.list_my_courses",
    "course_entitlements.list_entitlements_for_user"
  ]
}
```

### `inspect_media(asset_id | lesson_id)`

Purpose:

- Return one domain-level media answer for either:
  - one asset, or
  - one lesson's entire authored/runtime media set

Input:

```json
{
  "asset_id": "uuid",
  "lesson_id": "uuid"
}
```

Rules:

- exactly one of `asset_id` or `lesson_id` is required
- asset mode answers "what is true about this asset?"
- lesson mode answers "what is true about all media for this lesson?"

Returns:

```json
{
  "subject": {
    "mode": "asset | lesson",
    "asset_id": "uuid | null",
    "lesson_id": "uuid | null"
  },
  "status": "ok | warning | error | missing",
  "violations": [],
  "inconsistencies": [],
  "state_summary": {
    "control_plane_state": "projected_ready | consistent | inconsistent | partial | missing | failed",
    "asset_count": 0,
    "lesson_media_count": 0,
    "runtime_media_count": 0,
    "recent_failure_count": 0,
    "worker_status": "ok | degraded | stopped | disabled"
  },
  "truth_sources": {
    "media_control_plane": {},
    "logs": {}
  }
}
```

Stable violations:

- `asset_missing`
- `lesson_missing`
- `runtime_projection_inconsistent`
- `asset_failed`
- `recent_media_failures_detected`
- `media_transcode_worker_degraded`

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "inspection": {
    "tool": "inspect_media",
    "version": "1"
  },
  "subject": {
    "mode": "lesson",
    "asset_id": null,
    "lesson_id": "lesson-123"
  },
  "status": "error",
  "violations": [
    {
      "code": "runtime_projection_inconsistent",
      "message": "Lesson media projection does not match the expected runtime contract",
      "severity": "error",
      "source": "media_control_plane.validate_runtime_projection",
      "subject": {
        "lesson_id": "lesson-123",
        "lesson_media_id": "lesson-media-123",
        "asset_id": "asset-123",
        "runtime_media_id": "runtime-123"
      },
      "details": {
        "contract_diff_fields": ["fallback_policy", "media_object_id"]
      }
    },
    {
      "code": "recent_media_failures_detected",
      "message": "Recent media failures were observed for asset asset-123",
      "severity": "warning",
      "source": "logs.get_media_failures",
      "subject": {
        "lesson_id": "lesson-123",
        "asset_id": "asset-123"
      },
      "details": {
        "failure_count": 1,
        "summary": {
          "asset_processing": 1
        }
      }
    }
  ],
  "inconsistencies": [
    {
      "code": "runtime_contract_field_diff",
      "message": "Runtime contract field mismatch detected",
      "source": "media_control_plane.validate_runtime_projection",
      "details": {
        "field": "fallback_policy",
        "expected": "never",
        "actual": "if_no_ready_asset"
      }
    }
  ],
  "state_summary": {
    "control_plane_state": "inconsistent",
    "asset_count": 1,
    "lesson_media_count": 1,
    "runtime_media_count": 1,
    "recent_failure_count": 1,
    "worker_status": "ok"
  },
  "truth_sources": {
    "media_control_plane": {
      "lesson_id": "lesson-123",
      "state_classification": "inconsistent"
    },
    "logs": {
      "worker_status": "ok",
      "asset_failures": [
        {
          "asset_id": "asset-123",
          "summary": {
            "asset_processing": 1
          }
        }
      ]
    }
  },
  "sources_consulted": [
    "media_control_plane.validate_runtime_projection",
    "logs.get_media_failures",
    "logs.get_worker_health"
  ]
}
```

### `inspect_editor_state(course_id)`

Purpose:

- Return one persisted editor-contract snapshot for all lessons in a course.
- Answer whether lessons are canonical, normalizable, or save-unsafe for the
  Studio editor.

Input:

```json
{
  "course_id": "uuid"
}
```

Returns:

```json
{
  "subject": {
    "course_id": "uuid"
  },
  "status": "ok | warning | error | missing",
  "violations": [],
  "inconsistencies": [],
  "state_summary": {
    "lesson_count": 0,
    "canonical_lessons": 0,
    "normalizable_lessons": 0,
    "save_unsafe_lessons": 0,
    "legacy_markup_lessons": 0
  },
  "truth_sources": {
    "course": {},
    "lessons": [],
    "lesson_media_contracts": []
  }
}
```

Per-lesson normalized states:

- `editor_load_state`: `loadable | loadable_with_legacy_import | unsafe`
- `save_contract_state`: `canonical | normalizable | rejected`

Stable violations:

- `course_missing`
- `lesson_markdown_not_canonical`
- `lesson_markdown_not_save_safe`
- `lesson_markdown_legacy_document_link`
- `lesson_markdown_formatting_issue`
- `lesson_markdown_unresolved_media_reference`

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "inspection": {
    "tool": "inspect_editor_state",
    "version": "1"
  },
  "subject": {
    "course_id": "course-123"
  },
  "status": "warning",
  "violations": [
    {
      "code": "lesson_markdown_not_canonical",
      "message": "Lesson markdown can be normalized but is not currently canonical",
      "severity": "warning",
      "source": "courses_service.canonicalize_lesson_content",
      "subject": {
        "course_id": "course-123",
        "lesson_id": "lesson-2"
      },
      "details": {
        "stored_sha256": "a1d4...",
        "normalized_sha256": "b91f..."
      }
    },
    {
      "code": "lesson_markdown_legacy_document_link",
      "message": "Lesson markdown still contains legacy document-link syntax",
      "severity": "warning",
      "source": "lesson_content.markdown_contains_legacy_document_media_links",
      "subject": {
        "course_id": "course-123",
        "lesson_id": "lesson-2"
      },
      "details": {}
    }
  ],
  "inconsistencies": [
    {
      "code": "normalized_markdown_diff",
      "message": "Stored markdown differs from canonical normalized markdown",
      "source": "courses_service.canonicalize_lesson_content",
      "details": {
        "lesson_id": "lesson-2"
      }
    }
  ],
  "state_summary": {
    "lesson_count": 2,
    "canonical_lessons": 1,
    "normalizable_lessons": 1,
    "save_unsafe_lessons": 0,
    "legacy_markup_lessons": 1
  },
  "truth_sources": {
    "course": {
      "course_present": true
    },
    "lessons": [
      {
        "lesson_id": "lesson-1",
        "editor_load_state": "loadable",
        "save_contract_state": "canonical"
      },
      {
        "lesson_id": "lesson-2",
        "editor_load_state": "loadable_with_legacy_import",
        "save_contract_state": "normalizable"
      }
    ]
  },
  "sources_consulted": [
    "courses.fetch_course",
    "courses.list_course_lessons",
    "courses.list_lesson_media",
    "courses_service.canonicalize_lesson_content",
    "lesson_content.build_lesson_media_write_contract",
    "lesson_content.markdown_contains_legacy_document_media_links",
    "markdown_integrity.scan_markdown_content"
  ]
}
```

### `validate_content_markdown(lesson_id)`

Purpose:

- Validate one stored lesson markdown payload against the canonical lesson-media
  write contract and formatting integrity rules.

Input:

```json
{
  "lesson_id": "uuid"
}
```

Returns:

```json
{
  "subject": {
    "lesson_id": "uuid"
  },
  "status": "ok | warning | error | missing",
  "violations": [],
  "inconsistencies": [],
  "state_summary": {
    "canonical_state": "canonical | normalizable | invalid",
    "typed_reference_count": 0,
    "unresolved_reference_count": 0,
    "legacy_document_link_count": 0,
    "formatting_issue_count": 0
  },
  "truth_sources": {
    "lesson": {},
    "lesson_media_contract": {},
    "markdown_validation": {}
  }
}
```

Stable violations:

- `lesson_missing`
- `markdown_not_canonical`
- `markdown_normalization_failed`
- `unresolved_media_reference`
- `legacy_document_link_present`
- `formatting_issue_detected`

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "inspection": {
    "tool": "validate_content_markdown",
    "version": "1"
  },
  "subject": {
    "lesson_id": "lesson-456"
  },
  "status": "error",
  "violations": [
    {
      "code": "markdown_normalization_failed",
      "message": "Stored markdown could not be normalized into the canonical lesson-media contract",
      "severity": "error",
      "source": "courses_service.canonicalize_lesson_content",
      "subject": {
        "lesson_id": "lesson-456"
      },
      "details": {
        "error": "could not normalize raw media refs"
      }
    },
    {
      "code": "unresolved_media_reference",
      "message": "Stored markdown references media that is not resolvable through the lesson_media contract",
      "severity": "error",
      "source": "lesson_content.normalize_lesson_markdown_for_storage",
      "subject": {
        "lesson_id": "lesson-456"
      },
      "details": {
        "ref": "https://cdn.test/lesson-image.png"
      }
    }
  ],
  "inconsistencies": [
    {
      "code": "raw_media_reference_present",
      "message": "Raw media reference was found where a typed lesson_media token is required",
      "source": "lesson_content.normalize_lesson_markdown_for_storage",
      "details": {
        "kind": "image"
      }
    }
  ],
  "state_summary": {
    "canonical_state": "invalid",
    "typed_reference_count": 0,
    "unresolved_reference_count": 1,
    "legacy_document_link_count": 0,
    "formatting_issue_count": 0
  },
  "truth_sources": {
    "lesson": {
      "lesson_present": true,
      "course_id": "course-123"
    },
    "lesson_media_contract": {
      "allowed_lesson_media_ids": ["doc-1", "img-1"]
    },
    "markdown_validation": {
      "stored_sha256": "55ac...",
      "normalized_sha256": null
    }
  },
  "sources_consulted": [
    "courses.fetch_lesson",
    "courses.list_lesson_media",
    "courses_service.canonicalize_lesson_content",
    "lesson_content.build_lesson_media_write_contract",
    "lesson_content.normalize_lesson_markdown_for_storage",
    "lesson_content.markdown_contains_legacy_document_media_links",
    "markdown_integrity.scan_markdown_content"
  ]
}
```

### `inspect_course(course_id)`

Purpose:

- Return one course-domain answer covering structure, cover resolution, lesson
  markdown health, and lesson-media health summaries.

Input:

```json
{
  "course_id": "uuid"
}
```

Returns:

```json
{
  "subject": {
    "course_id": "uuid"
  },
  "status": "ok | warning | error | missing",
  "violations": [],
  "inconsistencies": [],
  "state_summary": {
    "publication_state": "published | draft | missing",
    "cover_state": "ready | legacy_fallback | placeholder | missing | failed",
    "lesson_count": 0,
    "intro_lesson_count": 0,
    "course_structure_state": "healthy | warning | inconsistent",
    "editor_contract_state": "healthy | warning | error",
    "lesson_media_state": "healthy | warning | error"
  },
  "truth_sources": {
    "course": {},
    "cover": {},
    "editor_state": {},
    "lesson_media": {}
  }
}
```

Stable violations:

- `course_missing`
- `course_cover_not_ready`
- `course_structure_position_conflict`
- `course_contains_invalid_markdown_lessons`
- `course_contains_media_projection_failures`

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "inspection": {
    "tool": "inspect_course",
    "version": "1"
  },
  "subject": {
    "course_id": "course-123"
  },
  "status": "warning",
  "violations": [
    {
      "code": "course_cover_not_ready",
      "message": "Course cover does not resolve to a ready control-plane asset",
      "severity": "warning",
      "source": "courses_service.resolve_course_cover",
      "subject": {
        "course_id": "course-123",
        "asset_id": "asset-cover-1"
      },
      "details": {
        "state": "legacy_fallback",
        "source": "legacy_cover_url"
      }
    },
    {
      "code": "course_contains_invalid_markdown_lessons",
      "message": "One or more lessons are not canonical editor-safe markdown",
      "severity": "warning",
      "source": "domain_observability.inspect_editor_state",
      "subject": {
        "course_id": "course-123"
      },
      "details": {
        "affected_lessons": ["lesson-2"]
      }
    }
  ],
  "inconsistencies": [
    {
      "code": "legacy_module_compatibility_shape",
      "message": "Course still exposes module compatibility state alongside flat lesson ownership",
      "source": "courses routes/repositories",
      "details": {
        "module_count": 1,
        "flat_lesson_count": 2
      }
    }
  ],
  "state_summary": {
    "publication_state": "draft",
    "cover_state": "legacy_fallback",
    "lesson_count": 2,
    "intro_lesson_count": 1,
    "course_structure_state": "warning",
    "editor_contract_state": "warning",
    "lesson_media_state": "healthy"
  },
  "truth_sources": {
    "course": {
      "slug": "foundations-step1",
      "title": "Foundations",
      "is_published": false,
      "step_level": "step1",
      "course_family": "foundations"
    },
    "cover": {
      "state": "legacy_fallback",
      "source": "legacy_cover_url"
    },
    "editor_state": {
      "status": "warning",
      "save_unsafe_lessons": 0,
      "normalizable_lessons": 1
    },
    "lesson_media": {
      "lessons_with_projection_errors": []
    }
  },
  "sources_consulted": [
    "courses.fetch_course",
    "courses.list_course_lessons",
    "courses.resolve_course_cover",
    "domain_observability.inspect_editor_state"
  ]
}
```

## Recommended Orchestration

Tool-to-service wiring should stay thin:

- `inspect_user(user_id)`
  - orchestrates auth/profile/membership/onboarding/course summary reads
- `inspect_media(...)`
  - delegates to existing media-control-plane and logs observability
- `inspect_editor_state(course_id)`
  - aggregates per-lesson markdown/editor-contract checks
- `validate_content_markdown(lesson_id)`
  - reuses the same per-lesson validator used by `inspect_editor_state`
- `inspect_course(course_id)`
  - aggregates:
    - `fetch_course`
    - `resolve_course_cover`
    - `inspect_editor_state`
    - bounded lesson-media health summaries

That keeps reuse high and avoids business-rule duplication.

## Why This Replaces Exploratory Debugging

Instead of asking Codex to manually do all of the following:

- fetch a course
- fetch its lessons
- inspect lesson markdown
- inspect lesson media
- inspect runtime projection
- inspect asset failures
- inspect cover resolution
- infer whether the result matters

the domain layer can answer directly:

- "this course is warning because the cover is legacy-fallback and lesson-2 is
  only normalizable, not canonical"
- "this user's onboarding state is drifted from the derived truth"
- "this lesson's media is broken because the runtime projection contract drifted"

That is the right abstraction level for Codex-facing introspection.
