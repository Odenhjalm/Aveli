# Verification MCP Server

Read-only MCP layer that sits above the existing observability surfaces and returns high-level truth-verification results without manual correlation.

## Route

- `POST /mcp/verification`
- `GET /mcp/verification`
- Local-only access, same JSON-RPC shape as the existing MCP routes
- Disabled by default in cloud runtimes via `verification_mcp_enabled`
- `POST /mcp/verification` currently supports:
  - `initialize`
  - `notifications/initialized`
  - `tools/list`
  - `tools/call`
- `GET /mcp/verification` is an availability endpoint, not a tool-execution surface

## Current mounted behavior

- The mounted route is included directly in `backend/app/main.py`.
- Successful `tools/call` responses are wrapped in the common MCP envelope:
  - `status`
  - `data`
  - `source`
  - `confidence`
- This MCP server is evidence-only:
  - it does not mutate runtime state
  - it does not implement an automatic repo-wide execution gate for VERIFIED_TASKS

## VERIFIED_TASK execution guidance

- Use this MCP server when a task needs bounded verification evidence for lesson media, course covers, or the phase-2 truth sample set.
- Run only the pre-checks and post-checks required by the current task scope.
- Treat verification output as operator evidence, not as an autonomous approval system.
- If task instructions require other MCP inputs as well, combine them manually with the relevant mounted routes.

## Service Structure

### Route

- `backend/app/routes/verification_mcp.py`
- Handles MCP protocol, tool registration, local-only access control, and deterministic JSON serialization

### Orchestration Service

- `backend/app/services/verification_observability.py`
- Pure read-only orchestration layer
- No inserts, updates, deletes, trigger calls, or storage writes

### Truth Sources Reused

- Logs truth:
  - `logs_observability.get_media_failures(asset_id)`
  - `logs_observability.get_recent_errors(limit)`
  - `logs_observability.get_worker_health()`
- Media control-plane truth:
  - `media_control_plane_observability.validate_runtime_projection(lesson_id)`
  - `media_control_plane_observability.get_asset(asset_id)`
- Resolver truth:
  - `media_resolver_service.inspect_lesson_media(lesson_media_id)`
  - `courses_service.resolve_course_cover(course_id, cover_media_id, cover_url)`
- Bounded discovery only:
  - `courses.list_courses(...)`
  - `courses.list_course_lessons(...)`
  - `courses.list_lesson_media(...)`

## Design Rules

- No new truth rules are invented in the verification layer
- Existing services remain the source of truth for:
  - runtime projection inconsistencies
  - canonical playback resolution
  - course cover resolution
  - worker and failure signals
- Verification only:
  - calls existing read paths
  - normalizes them into a single result
  - lifts existing inconsistencies into explicit verification violations

## Common Output Contract

Every verification tool returns deterministic JSON with:

```json
{
  "generated_at": "ISO-8601 timestamp",
  "verification": {
    "tool": "stable_tool_name",
    "version": "1"
  },
  "verdict": "pass | fail",
  "confidence": "high | medium | low",
  "violations": [
    {
      "code": "stable_code",
      "message": "human-readable explanation",
      "severity": "error | warning | info",
      "source": "upstream_truth_source",
      "course_id": "uuid | null",
      "lesson_id": "uuid | null",
      "lesson_media_id": "uuid | null",
      "asset_id": "uuid | null",
      "runtime_media_id": "uuid | null",
      "details": {}
    }
  ],
  "summary": {},
  "truth_sources": {},
  "sources_consulted": ["stable source names"]
}
```

### Verdict Rules

- `fail`: at least one `severity == "error"` violation
- `pass`: no error-severity violations

### Confidence Rules

- `high`: logs + control-plane truth + resolver truth were all consulted
- `medium`: two truth categories were available
- `low`: only one truth category was available or the primary subject was missing

## Tool Contracts

### `verify_lesson_media_truth(lesson_id)`

Purpose:

- Verify one lesson end-to-end using:
  - lesson/runtime projection validation
  - canonical resolver truth per playback `lesson_media`
  - recent asset failures and worker health

Returns:

```json
{
  "lesson_id": "uuid",
  "verdict": "pass | fail",
  "confidence": "high | medium | low",
  "violations": [],
  "summary": {
    "lesson_media_count": 0,
    "asset_count": 0,
    "resolver_checks": 0,
    "error_count": 0,
    "warning_count": 0,
    "control_plane_state_classification": "consistent | inconsistent | partial | missing",
    "media_transcode_worker_status": "ok | degraded | stopped | disabled"
  },
  "truth_sources": {
    "media_control_plane": {},
    "resolver": {
      "lesson_media": []
    },
    "logs": {
      "worker_health": {},
      "asset_failures": []
    }
  }
}
```

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "verification": {
    "tool": "verify_lesson_media_truth",
    "version": "1"
  },
  "lesson_id": "lesson-123",
  "verdict": "fail",
  "confidence": "high",
  "violations": [
    {
      "code": "runtime_media_missing",
      "message": "lesson_media has no runtime_media projection",
      "severity": "error",
      "source": "media_control_plane.validate_runtime_projection",
      "course_id": "course-123",
      "lesson_id": "lesson-123",
      "lesson_media_id": "lesson-media-123",
      "asset_id": "asset-123",
      "runtime_media_id": null,
      "details": {}
    },
    {
      "code": "recent_media_failures_detected",
      "message": "Recent media failures were observed for asset asset-123",
      "severity": "warning",
      "source": "logs.get_media_failures",
      "course_id": null,
      "lesson_id": "lesson-123",
      "lesson_media_id": null,
      "asset_id": "asset-123",
      "runtime_media_id": null,
      "details": {
        "summary": {
          "asset_processing": 1
        },
        "failure_count": 1
      }
    }
  ],
  "summary": {
    "lesson_media_count": 1,
    "asset_count": 1,
    "resolver_checks": 1,
    "error_count": 1,
    "warning_count": 1,
    "control_plane_state_classification": "inconsistent",
    "media_transcode_worker_status": "ok"
  }
}
```

### `verify_course_cover_truth(course_id)`

Purpose:

- Verify one course cover using:
  - canonical course-cover resolver truth
  - media control-plane asset snapshot
  - recent asset failures and worker health

Returns:

```json
{
  "course_id": "uuid",
  "course": {
    "course_id": "uuid",
    "slug": "string | null",
    "title": "string | null",
    "cover_media_id": "uuid | null",
    "cover_url": "string | null"
  },
  "verdict": "pass | fail",
  "confidence": "high | medium | low",
  "violations": [],
  "summary": {
    "resolved_state": "ready | legacy_fallback | missing | placeholder | uploaded | processing | failed",
    "resolved_source": "control_plane | legacy_cover_url | placeholder | missing",
    "asset_state_classification": "projected_ready | asset_failed | missing | ...",
    "media_transcode_worker_status": "ok | degraded | stopped | disabled"
  },
  "truth_sources": {
    "resolver": {},
    "media_control_plane": {},
    "logs": {}
  }
}
```

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "verification": {
    "tool": "verify_course_cover_truth",
    "version": "1"
  },
  "course_id": "course-123",
  "verdict": "fail",
  "confidence": "high",
  "violations": [
    {
      "code": "course_cover_not_control_plane_ready",
      "message": "Course cover did not resolve to a ready control-plane asset",
      "severity": "error",
      "source": "courses_service.resolve_course_cover",
      "course_id": "course-123",
      "lesson_id": null,
      "lesson_media_id": null,
      "asset_id": "asset-123",
      "runtime_media_id": null,
      "details": {
        "state": "legacy_fallback",
        "source": "legacy_cover_url",
        "resolved_url": "/api/files/public-media/courses/legacy-cover.jpg"
      }
    }
  ],
  "summary": {
    "resolved_state": "legacy_fallback",
    "resolved_source": "legacy_cover_url",
    "asset_state_classification": "asset_failed",
    "media_transcode_worker_status": "ok"
  }
}
```

### `verify_phase2_truth_alignment()`

Purpose:

- Run a bounded top-level verification of phase-2 truth alignment
- Uses:
  - discovered test cases
  - sampled lesson verification results
  - sampled course-cover verification results
  - recent error signals
  - worker health

Returns:

```json
{
  "verdict": "pass | fail",
  "confidence": "high | medium | low",
  "violations": [],
  "summary": {
    "lesson_samples_checked": 0,
    "course_cover_samples_checked": 0,
    "recent_error_count": 0,
    "error_count": 0,
    "warning_count": 0,
    "media_transcode_worker_status": "ok | degraded | stopped | disabled"
  },
  "truth_sources": {
    "test_cases": {},
    "logs": {},
    "samples": {
      "lesson_media_truth": [],
      "course_cover_truth": []
    }
  }
}
```

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "verification": {
    "tool": "verify_phase2_truth_alignment",
    "version": "1"
  },
  "verdict": "fail",
  "confidence": "high",
  "violations": [
    {
      "code": "lesson_truth_sample_failed",
      "message": "A sampled lesson truth verification failed",
      "severity": "error",
      "source": "verify_lesson_media_truth",
      "course_id": null,
      "lesson_id": "lesson-123",
      "lesson_media_id": null,
      "asset_id": null,
      "runtime_media_id": null,
      "details": {
        "confidence": "high",
        "violation_codes": ["runtime_media_missing"]
      }
    }
  ],
  "summary": {
    "lesson_samples_checked": 1,
    "course_cover_samples_checked": 1,
    "recent_error_count": 0,
    "error_count": 1,
    "warning_count": 0,
    "media_transcode_worker_status": "ok"
  }
}
```

### `get_test_cases()`

Purpose:

- Discover bounded deterministic ids worth verifying right now
- Avoids open-ended exploration by returning direct tool call candidates

Returns:

```json
{
  "verdict": "pass | fail",
  "confidence": "high | medium | low",
  "violations": [],
  "scan_limits": {
    "course_scan_limit": 12,
    "course_case_limit": 4,
    "lesson_case_limit": 4,
    "lessons_per_course": 6
  },
  "course_cover_cases": [],
  "lesson_media_cases": [],
  "recommended_calls": []
}
```

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "verification": {
    "tool": "get_test_cases",
    "version": "1"
  },
  "verdict": "pass",
  "confidence": "high",
  "violations": [],
  "scan_limits": {
    "course_scan_limit": 12,
    "course_case_limit": 4,
    "lesson_case_limit": 4,
    "lessons_per_course": 6
  },
  "course_cover_cases": [
    {
      "course_id": "course-123",
      "slug": "course-123",
      "title": "Course 123",
      "why": "course has cover_media_id"
    }
  ],
  "lesson_media_cases": [
    {
      "lesson_id": "lesson-123",
      "course_id": "course-123",
      "course_title": "Course 123",
      "lesson_title": "Lesson 123",
      "why": "lesson has lesson_media kind=audio"
    }
  ],
  "recommended_calls": [
    {
      "tool": "verify_lesson_media_truth",
      "arguments": {
        "lesson_id": "lesson-123"
      }
    },
    {
      "tool": "verify_course_cover_truth",
      "arguments": {
        "course_id": "course-123"
      }
    }
  ]
}
```

## Notes

- This layer does not replace the underlying observability tools
- It composes them into verification-first outputs so Codex can validate behavior directly
- The layer is intentionally minimal:
  - no new mutation paths
  - no duplicated resolver policy
  - no duplicated control-plane validation logic
  - no fuzzy prose-only summaries without machine-readable violations
