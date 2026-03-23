# Media Control Plane MCP Server

Minimal read-only MCP server for deterministic inspection of `media_assets`,
`lesson_media`, and `runtime_media`.

## Transport

- Endpoint: `POST /mcp/media-control-plane`
- Companion GET endpoint: `GET /mcp/media-control-plane`
- Transport: Streamable HTTP style JSON-RPC over the existing FastAPI app
- Default local MCP config target: `http://127.0.0.1:8080/mcp/media-control-plane`

## Safety

- Read-only only: no inserts, updates, deletes, trigger invocations, or storage writes
- Uses repository and service layer reads only
- Runtime projection validation reuses the canonical resolver without emitting new telemetry
- Local-only access: rejects non-local clients and non-local `Origin` headers
- Disabled by default in cloud runtimes via `media_control_plane_mcp_enabled`
- Bounded reads:
  - `get_asset(asset_id)`: related rows capped at `25` per reference set
  - `trace_asset_lifecycle(asset_id)`: log and failure timelines capped at `25`
  - `list_orphaned_assets()`: capped at `100`
  - `validate_runtime_projection(lesson_id)`: capped at `100` lesson/runtime rows
- Sensitive fields are omitted or sanitized:
  - no owner ids, teacher ids, emails, signed URLs, tokens, or cookies
  - log messages and issue details are passed through the shared redaction layer

## Inspection Summary

### Read paths

- `media_assets`
  - `backend/app/repositories/media_assets.py`
  - primary reads: `get_media_asset`, `get_media_assets`
- `lesson_media`
  - `backend/app/repositories/courses.py`
  - primary reads: `list_lesson_media`, new asset-scoped read for `list_lesson_media_for_asset`
- `runtime_media`
  - `backend/app/repositories/runtime_media.py`
  - primary reads: lesson-scoped and asset-scoped runtime projection lookups

### Validation logic already in the backend

- Asset lifecycle and ready-contract validation:
  - `backend/app/routes/api_media.py`
  - `backend/app/services/media_transcode_worker.py`
- Projection correctness and fallback rules:
  - `backend/app/media_control_plane/services/media_resolver_service.py`
- Runtime projection source-of-truth shape:
  - DB-triggered `app.upsert_runtime_media_for_lesson_media(...)`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql`

### Canonical model

- `media_assets` owns bytes, ingest, derivatives, and lifecycle state
- `lesson_media` is the authored lesson reference layer
- `runtime_media` is the delivery/auth projection layer
- `storage.objects` remains the byte-existence authority when available

## Tool Contract

Common contract guarantees:

- Every tool returns normalized JSON
- Every tool returns `state_classification`
- Every tool returns `detected_inconsistencies`
- Correlation fields include asset ids, timestamps, and state transitions
- Every tool returns additive `validation` metadata:
  - `validation_mode: "strict_contract"`
  - `evaluated_at: ISO-8601 timestamp`
  - `data_freshness: "snapshot"`
- Storage verification confidence:
  - `full`: every attempted storage check had enough bucket/path identity and the storage catalog was available
  - `partial`: storage verification was attempted. When at least one storage lookup was skipped or an involved target could not be fully checked, confidence degrades to partial
  - `unavailable`: no storage lookup was performed or the storage catalog was unavailable
- `trace_asset_lifecycle` is a reconstructed snapshot timeline, not authoritative event history

### `get_asset(asset_id)`

Returns:

```json
{
  "generated_at": "ISO-8601 timestamp",
  "validation": {
    "validation_mode": "strict_contract",
    "evaluated_at": "ISO-8601 timestamp",
    "data_freshness": "snapshot"
  },
  "asset_id": "uuid",
  "state_classification": "missing | out_of_scope | awaiting_link | unlinked_stalled | strict_orphan | inconsistent | asset_in_progress | failed_unlinked | asset_failed | projected_ready | observed",
  "detected_inconsistencies": [],
  "asset": {
    "asset_id": "uuid",
    "course_id": "uuid | null",
    "lesson_id": "uuid | null",
    "media_type": "audio | video | image | document | other | null",
    "purpose": "lesson_audio | lesson_media | home_player_audio | ...",
    "state": "pending_upload | uploaded | processing | ready | failed | null",
    "storage": {
      "source_bucket": "bucket | null",
      "source_path": "path | null",
      "playback_bucket": "bucket | null",
      "playback_path": "path | null",
      "playback_format": "format | null"
    },
    "created_at": "ISO-8601 timestamp | null",
    "updated_at": "ISO-8601 timestamp | null"
  },
  "lesson_media_references": [],
  "runtime_projection": [],
  "storage_verification": {
    "storage_catalog_available": true,
    "confidence": "full | partial | unavailable",
    "checks": []
  },
  "correlation": {
    "asset_ids": ["uuid"],
    "lesson_ids": [],
    "lesson_media_ids": [],
    "runtime_media_ids": [],
    "timestamps": [],
    "state_transitions": []
  },
  "truncation": {
    "lesson_media_references_truncated": false,
    "runtime_projection_truncated": false
  }
}
```

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "validation": {
    "validation_mode": "strict_contract",
    "evaluated_at": "2026-03-23T12:00:00+00:00",
    "data_freshness": "snapshot"
  },
  "asset_id": "1d3d2e2b-7273-46ea-a7f8-545e5fd3c762",
  "state_classification": "projected_ready",
  "detected_inconsistencies": [],
  "asset": {
    "asset_id": "1d3d2e2b-7273-46ea-a7f8-545e5fd3c762",
    "course_id": "9f8cb235-3224-4520-95be-0b09e0bc56f4",
    "lesson_id": "f43aa285-b3d3-4b2c-99c8-14a8a9039517",
    "media_type": "audio",
    "purpose": "lesson_audio",
    "state": "ready",
    "storage": {
      "source_bucket": "course-media",
      "source_path": "media/source/audio/courses/9f8c/lessons/f43a/demo.wav",
      "playback_bucket": "course-media",
      "playback_path": "media/derived/audio/courses/9f8c/lessons/f43a/demo.mp3",
      "playback_format": "mp3"
    },
    "created_at": "2026-03-23T11:41:02+00:00",
    "updated_at": "2026-03-23T11:42:18+00:00"
  },
  "lesson_media_references": [
    {
      "lesson_media_id": "6d62e937-59d7-432a-bf15-f5b057c0ef11",
      "lesson_id": "f43aa285-b3d3-4b2c-99c8-14a8a9039517",
      "kind": "audio",
      "asset_id": "1d3d2e2b-7273-46ea-a7f8-545e5fd3c762",
      "media_state": "ready"
    }
  ],
  "runtime_projection": [
    {
      "runtime_media_id": "3da05e9d-d403-40bb-966f-e4b8ebf0ef07",
      "state_classification": "playable",
      "resolution": {
        "is_playable": true,
        "playback_mode": "pipeline_asset",
        "failure_reason": "ok_ready_asset"
      }
    }
  ],
  "storage_verification": {
    "storage_catalog_available": true,
    "confidence": "full",
    "checks": []
  }
}
```

### `trace_asset_lifecycle(asset_id)`

Returns:

```json
{
  "generated_at": "ISO-8601 timestamp",
  "validation": {
    "validation_mode": "strict_contract",
    "evaluated_at": "ISO-8601 timestamp",
    "data_freshness": "snapshot"
  },
  "asset_id": "uuid",
  "storage_verification": {
    "storage_catalog_available": "boolean",
    "confidence": "full | partial | unavailable",
    "checks": []
  },
  "timeline_mode": "reconstructed_snapshot_timeline",
  "state_classification": "missing | in_progress | failed | inconsistent | ready",
  "detected_inconsistencies": [],
  "asset": {},
  "state_transitions": [
    {
      "timestamp": "ISO-8601 timestamp",
      "transition": "asset_record_created | lesson_media_linked | runtime_projection_created | resolution_failure_recorded | ...",
      "source": "media_assets | lesson_media | runtime_media | media_resolution_failures",
      "asset_id": "uuid | null",
      "lesson_id": "uuid | null",
      "lesson_media_id": "uuid | null",
      "runtime_media_id": "uuid | null",
      "state": "string | null",
      "certainty": "observed | inferred | reconstructed",
      "details": {}
    }
  ],
  "related_resolution_failures": [],
  "related_log_events": [],
  "correlation": {}
}
```

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "validation": {
    "validation_mode": "strict_contract",
    "evaluated_at": "2026-03-23T12:00:00+00:00",
    "data_freshness": "snapshot"
  },
  "asset_id": "1d3d2e2b-7273-46ea-a7f8-545e5fd3c762",
  "storage_verification": {
    "storage_catalog_available": true,
    "confidence": "full",
    "checks": []
  },
  "timeline_mode": "reconstructed_snapshot_timeline",
  "state_classification": "ready",
  "detected_inconsistencies": [],
  "state_transitions": [
    {
      "timestamp": "2026-03-23T11:41:02+00:00",
      "transition": "asset_record_created",
      "source": "media_assets",
      "asset_id": "1d3d2e2b-7273-46ea-a7f8-545e5fd3c762",
      "state": "pending_upload",
      "certainty": "inferred",
      "details": {
        "purpose": "lesson_audio"
      }
    },
    {
      "timestamp": "2026-03-23T11:41:25+00:00",
      "transition": "lesson_media_linked",
      "source": "lesson_media",
      "asset_id": "1d3d2e2b-7273-46ea-a7f8-545e5fd3c762",
      "lesson_media_id": "6d62e937-59d7-432a-bf15-f5b057c0ef11",
      "state": "uploaded",
      "certainty": "reconstructed",
      "details": {
        "kind": "audio"
      }
    },
    {
      "timestamp": "2026-03-23T11:42:18+00:00",
      "transition": "asset_state_observed",
      "source": "media_assets",
      "asset_id": "1d3d2e2b-7273-46ea-a7f8-545e5fd3c762",
      "state": "ready",
      "certainty": "reconstructed",
      "details": {}
    }
  ]
}
```

### `list_orphaned_assets()`

Compatibility note:

- The tool name stays `list_orphaned_assets()` for MCP stability.
- The payload is now explicitly documented as a broader unlinked control-plane asset inspection.
- `strict_orphan` means no `lesson_media`, no `runtime_media`, and no home-upload runtime gap.
- `awaiting_link` is only used while the asset is still within the grace window.

Returns:

```json
{
  "generated_at": "ISO-8601 timestamp",
  "validation": {
    "validation_mode": "strict_contract",
    "evaluated_at": "ISO-8601 timestamp",
    "data_freshness": "snapshot"
  },
  "inspection_scope": "unlinked_control_plane_assets",
  "state_classification": "healthy | warning | inconsistent",
  "detected_inconsistencies": [],
  "orphaned_assets": [
    {
      "asset": {},
      "state_classification": "awaiting_link | unlinked_stalled | strict_orphan | failed_unlinked | runtime_projection_gap",
      "detected_inconsistencies": [],
      "reference_counts": {
        "lesson_media": 0,
        "runtime_media": 0,
        "home_player_uploads": 0
      },
      "linkage_timing": {
        "evaluated_at": "ISO-8601 timestamp",
        "age_seconds": 0,
        "grace_window_seconds": 1800,
        "within_grace_window": true
      },
      "correlation": {}
    }
  ],
  "summary": {
    "limit_applied": 100,
    "truncated": false,
    "total_assets": 0,
    "grace_window_seconds": 1800,
    "classification_counts": {}
  }
}
```

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "validation": {
    "validation_mode": "strict_contract",
    "evaluated_at": "2026-03-23T12:00:00+00:00",
    "data_freshness": "snapshot"
  },
  "inspection_scope": "unlinked_control_plane_assets",
  "state_classification": "warning",
  "detected_inconsistencies": [],
  "orphaned_assets": [
    {
      "asset": {
        "asset_id": "2c16d32b-6f6c-45d3-a9d8-44fdc1bf4d2e",
        "purpose": "lesson_media",
        "state": "ready"
      },
      "state_classification": "strict_orphan",
      "detected_inconsistencies": [],
      "reference_counts": {
        "lesson_media": 0,
        "runtime_media": 0,
        "home_player_uploads": 0
      },
      "linkage_timing": {
        "evaluated_at": "2026-03-23T12:00:00+00:00",
        "age_seconds": 42,
        "grace_window_seconds": null,
        "within_grace_window": null
      }
    }
  ],
  "summary": {
    "limit_applied": 100,
    "truncated": false,
    "total_assets": 1,
    "grace_window_seconds": 1800,
    "classification_counts": {
      "strict_orphan": 1
    }
  }
}
```

### `validate_runtime_projection(lesson_id)`

Returns:

```json
{
  "generated_at": "ISO-8601 timestamp",
  "validation": {
    "validation_mode": "strict_contract",
    "evaluated_at": "ISO-8601 timestamp",
    "data_freshness": "snapshot"
  },
  "lesson_id": "uuid",
  "storage_verification": {
    "storage_catalog_available": "boolean",
    "confidence": "full | partial | unavailable"
  },
  "state_classification": "missing | consistent | inconsistent | partial",
  "detected_inconsistencies": [],
  "lesson": {
    "lesson_id": "uuid",
    "course_id": "uuid",
    "title": "string | null"
  },
  "lesson_media": [
    {
      "lesson_media": {},
      "asset": {},
      "runtime_projection": {},
      "expected_runtime_contract": {
        "reference_type": "lesson_media",
        "auth_scope": "lesson_course",
        "fallback_policy": "never | if_no_ready_asset | legacy_only",
        "course_id": "uuid | null",
        "lesson_id": "uuid | null",
        "media_asset_id": "uuid | null",
        "media_object_id": "uuid | null",
        "legacy_storage_bucket": "string | null",
        "legacy_storage_path": "string | null",
        "kind": "audio | video | image | document | other",
        "active": true
      },
      "actual_runtime_contract": {
        "reference_type": "lesson_media | home_player_upload | null",
        "auth_scope": "lesson_course | home_teacher_library | null",
        "fallback_policy": "never | if_no_ready_asset | legacy_only | null",
        "course_id": "uuid | null",
        "lesson_id": "uuid | null",
        "media_asset_id": "uuid | null",
        "media_object_id": "uuid | null",
        "legacy_storage_bucket": "string | null",
        "legacy_storage_path": "string | null",
        "kind": "audio | video | image | document | other | null",
        "active": "boolean | null"
      },
      "contract_diffs": [
        {
          "field": "reference_type | auth_scope | fallback_policy | course_id | lesson_id | media_asset_id | media_object_id | legacy_storage_bucket | legacy_storage_path | kind | active",
          "expected": "normalized value",
          "actual": "normalized value"
        }
      ],
      "state_classification": "asset_missing | runtime_missing | in_progress | non_playback | legacy_fallback | consistent | inconsistent | unresolved",
      "detected_inconsistencies": [],
      "correlation": {}
    }
  ],
  "runtime_rows_without_lesson_media": [],
  "summary": {
    "limit_applied": 100,
    "truncated": false,
    "lesson_media_count": 0,
    "runtime_row_count": 0,
    "runtime_rows_without_lesson_media_count": 0,
    "classification_counts": {}
  },
  "correlation": {}
}
```

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "validation": {
    "validation_mode": "strict_contract",
    "evaluated_at": "2026-03-23T12:00:00+00:00",
    "data_freshness": "snapshot"
  },
  "lesson_id": "f43aa285-b3d3-4b2c-99c8-14a8a9039517",
  "storage_verification": {
    "storage_catalog_available": true,
    "confidence": "full"
  },
  "state_classification": "consistent",
  "detected_inconsistencies": [],
  "lesson": {
    "lesson_id": "f43aa285-b3d3-4b2c-99c8-14a8a9039517",
    "course_id": "9f8cb235-3224-4520-95be-0b09e0bc56f4",
    "title": "Breath Reset"
  },
  "lesson_media": [
    {
      "lesson_media": {
        "lesson_media_id": "6d62e937-59d7-432a-bf15-f5b057c0ef11",
        "kind": "audio",
        "asset_id": "1d3d2e2b-7273-46ea-a7f8-545e5fd3c762",
        "media_state": "ready"
      },
      "asset": {
        "asset_id": "1d3d2e2b-7273-46ea-a7f8-545e5fd3c762",
        "state": "ready",
        "purpose": "lesson_audio"
      },
      "runtime_projection": {
        "runtime_media_id": "3da05e9d-d403-40bb-966f-e4b8ebf0ef07",
        "state_classification": "playable",
        "resolution": {
          "is_playable": true,
          "playback_mode": "pipeline_asset",
          "failure_reason": "ok_ready_asset"
        }
      },
      "expected_runtime_contract": {
        "reference_type": "lesson_media",
        "auth_scope": "lesson_course",
        "fallback_policy": "never",
        "course_id": "9f8cb235-3224-4520-95be-0b09e0bc56f4",
        "lesson_id": "f43aa285-b3d3-4b2c-99c8-14a8a9039517",
        "media_asset_id": "1d3d2e2b-7273-46ea-a7f8-545e5fd3c762",
        "media_object_id": null,
        "legacy_storage_bucket": null,
        "legacy_storage_path": null,
        "kind": "audio",
        "active": true
      },
      "actual_runtime_contract": {
        "reference_type": "lesson_media",
        "auth_scope": "lesson_course",
        "fallback_policy": "never",
        "course_id": "9f8cb235-3224-4520-95be-0b09e0bc56f4",
        "lesson_id": "f43aa285-b3d3-4b2c-99c8-14a8a9039517",
        "media_asset_id": "1d3d2e2b-7273-46ea-a7f8-545e5fd3c762",
        "media_object_id": null,
        "legacy_storage_bucket": null,
        "legacy_storage_path": null,
        "kind": "audio",
        "active": true
      },
      "contract_diffs": [],
      "state_classification": "consistent",
      "detected_inconsistencies": []
    }
  ],
  "runtime_rows_without_lesson_media": [],
  "summary": {
    "limit_applied": 100,
    "truncated": false,
    "lesson_media_count": 1,
    "runtime_row_count": 1,
    "runtime_rows_without_lesson_media_count": 0,
    "classification_counts": {
      "consistent": 1
    }
  }
}
```

## How It Complements Logs MCP

## Backward Compatibility

- Existing fields are unchanged; this pass only adds optional metadata fields.
- Consumers already reading the previous payload shape can ignore `validation` and `storage_verification.confidence`.
- JSON output remains deterministic because route serialization still uses sorted keys and the new values are scalar snapshot metadata.

- Logs MCP answers: "What failed recently?"
- Media Control Plane MCP answers: "What is the authoritative media state right now?"
- Correlation works through shared identifiers and time markers:
  - `asset_id`
  - `lesson_media_id`
  - `runtime_media_id`
  - normalized timestamps
  - explicit state transitions
- A typical flow is:
  1. Use Logs MCP to spot a failing `asset_id` or runtime failure reason.
  2. Use `get_asset(asset_id)` to inspect the current control-plane graph.
  3. Use `trace_asset_lifecycle(asset_id)` to line up state transitions with recent logs.
  4. Use `validate_runtime_projection(lesson_id)` when failures look like projection drift rather than worker failure.
