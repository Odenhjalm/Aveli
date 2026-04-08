# Logs MCP Server

Minimal read-only MCP server for backend observability.

## Transport

- Endpoint: `POST /mcp/logs`
- Companion GET endpoint: `GET /mcp/logs`
- Transport: Streamable HTTP style JSON-RPC over the existing FastAPI app
- Default local MCP config target: `http://127.0.0.1:8080/mcp/logs`

## Safety

- Read-only only: no inserts, updates, deletes, or storage writes
- Local-only access: rejects non-local clients and non-local `Origin` headers
- Disabled by default in cloud runtimes via `logs_mcp_enabled`
- Bounded results:
  - `get_recent_errors(limit)`: `1..50`
  - `get_media_failures(asset_id?)`: fixed max `25`
  - `get_cleanup_activity(window)`: windows limited to `1h`, `6h`, `24h`, `7d`
  - in-memory observability buffer capped at `500` sanitized events
- Sensitive fields are redacted in MCP output:
  - `user_id`, `teacher_id`, `owner_id`, `email`
  - bearer tokens, signed URLs, querystring tokens, secrets, cookies

## Inspection Summary

### Where logs are produced

- Media processing:
  - `backend/app/services/media_transcode_worker.py`
- Upload pipeline:
  - `backend/app/routes/api_media.py`
  - `backend/app/routes/upload.py`
  - `backend/app/routes/studio.py`
- Cleanup jobs / cleanup paths:
  - `backend/app/services/media_cleanup.py`
  - `backend/app/services/courses_service.py` triggers media garbage collection after deletes
- Worker processes:
  - `backend/app/services/media_transcode_worker.py`
  - `backend/app/services/livekit_events.py`
  - `backend/app/services/membership_expiry_warnings.py`

### Formats and sources

- Primary runtime log format: JSON lines via `backend/app/logging_utils.py`
- Primary runtime log sink: stdout `logging.StreamHandler`
- Request correlation source: middleware-backed request context in `backend/app/middleware/request_context.py`
- Durable observability sources already present in Postgres:
  - `app.media_assets`
  - `app.media_resolution_failures`
  - `app.livekit_webhook_jobs`
- Native backend file logging: none by default

## Tool Contract

### `get_recent_errors(limit=20)`

Returns:

```json
{
  "generated_at": "ISO-8601 timestamp",
  "limit_applied": 20,
  "recent_errors": [
    {
      "source": "log_buffer | media_assets | media_resolution_failures | livekit_webhook_jobs",
      "timestamp": "ISO-8601 timestamp",
      "severity": "ERROR",
      "component": "application | upload_pipeline | media_processing | cleanup | worker",
      "event": "stable_event_name",
      "message": "sanitized human-readable message",
      "details": {}
    }
  ],
  "sources_consulted": [
    "log_buffer",
    "media_assets",
    "media_resolution_failures",
    "livekit_webhook_jobs"
  ]
}
```

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "limit_applied": 2,
  "recent_errors": [
    {
      "source": "media_assets",
      "timestamp": "2026-03-23T11:58:04+00:00",
      "severity": "ERROR",
      "component": "media_processing",
      "event": "media_asset_failed",
      "message": "ffmpeg failed",
      "details": {
        "failure_type": "asset_processing",
        "asset_id": "b6fb8aa0-4cf2-4b17-bcfe-4eb3f7dd2c8a",
        "course_id": "8b71e3d7-1de8-4552-a3bb-367eab7cff0e",
        "lesson_id": "4fe46f4d-4cf2-4d5d-8d0d-7625b5a7603e",
        "media_type": "audio",
        "purpose": "lesson_audio",
        "processing_attempts": 3,
        "state": "failed"
      }
    },
    {
      "source": "log_buffer",
      "timestamp": "2026-03-23T11:57:41Z",
      "severity": "ERROR",
      "component": "upload_pipeline",
      "event": "upload_pipeline_upload_url_issuance_failed",
      "message": "Upload URL issuance failed: Storage signing unavailable",
      "details": {
        "request_id": "18bb7f4fd95749af973e1470c879bd02"
      }
    }
  ],
  "sources_consulted": [
    "log_buffer",
    "media_assets",
    "media_resolution_failures",
    "livekit_webhook_jobs"
  ]
}
```

### `get_media_failures(asset_id?)`

Returns:

```json
{
  "generated_at": "ISO-8601 timestamp",
  "asset_id": "uuid or null",
  "media_failures": [
    {
      "source": "media_assets | media_resolution_failures | log_buffer",
      "timestamp": "ISO-8601 timestamp",
      "severity": "WARNING | ERROR",
      "component": "upload_pipeline | media_processing",
      "event": "stable_event_name",
      "message": "sanitized human-readable message",
      "details": {}
    }
  ],
  "summary": {
    "asset_processing": 0,
    "resolution": 0,
    "log_buffer": 0
  }
}
```

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "asset_id": "b6fb8aa0-4cf2-4b17-bcfe-4eb3f7dd2c8a",
  "media_failures": [
    {
      "source": "media_assets",
      "timestamp": "2026-03-23T11:58:04+00:00",
      "severity": "ERROR",
      "component": "media_processing",
      "event": "media_asset_failed",
      "message": "ffmpeg failed",
      "details": {
        "failure_type": "asset_processing",
        "asset_id": "b6fb8aa0-4cf2-4b17-bcfe-4eb3f7dd2c8a",
        "processing_attempts": 3,
        "next_retry_at": "2026-03-23T12:03:04+00:00",
        "source_bucket": "course-media",
        "source_path": "media/source/audio/course/lesson/source.wav"
      }
    },
    {
      "source": "log_buffer",
      "timestamp": "2026-03-23T11:58:04Z",
      "severity": "ERROR",
      "component": "media_processing",
      "event": "media_processing_media_transcode_failed_for",
      "message": "Media transcode failed for b6fb8aa0-4cf2-4b17-bcfe-4eb3f7dd2c8a: ffmpeg failed",
      "details": {
        "media_id": "b6fb8aa0-4cf2-4b17-bcfe-4eb3f7dd2c8a"
      }
    }
  ],
  "summary": {
    "asset_processing": 1,
    "log_buffer": 1
  }
}
```

### `get_cleanup_activity(window="24h")`

Returns:

```json
{
  "generated_at": "ISO-8601 timestamp",
  "window": "1h | 6h | 24h | 7d",
  "window_start": "ISO-8601 timestamp",
  "cleanup_activity": [
    {
      "source": "log_buffer",
      "timestamp": "ISO-8601 timestamp",
      "severity": "INFO | WARNING | ERROR",
      "component": "cleanup",
      "event": "stable_event_name",
      "message": "sanitized human-readable message",
      "details": {}
    }
  ],
  "summary": {
    "total_events": 0,
    "event_counts": {}
  }
}
```

Example:

```json
{
  "generated_at": "2026-03-23T12:00:00+00:00",
  "window": "24h",
  "window_start": "2026-03-22T12:00:00+00:00",
  "cleanup_activity": [
    {
      "source": "log_buffer",
      "timestamp": "2026-03-23T11:44:07Z",
      "severity": "INFO",
      "component": "cleanup",
      "event": "media_cleanup_garbage_collect_summary",
      "message": "MEDIA_CLEANUP_GARBAGE_COLLECT_SUMMARY",
      "details": {
        "batch_size": 200,
        "max_batches": 10,
        "media_assets_course_cover_deleted": 1,
        "media_assets_lesson_audio_deleted": 2,
        "media_objects_deleted": 4
      }
    }
  ],
  "summary": {
    "total_events": 1,
    "event_counts": {
      "media_cleanup_garbage_collect_summary": 1
    }
  }
}
```

### `get_worker_health()`

Returns:

```json
{
  "generated_at": "ISO-8601 timestamp",
  "worker_health": {
    "media_transcode": {
      "status": "ok | degraded | stopped | disabled",
      "worker_running": true,
      "enabled_by_env": true,
      "enabled_by_config": true,
      "poll_interval_seconds": 10,
      "batch_size": 3,
      "max_attempts": 5,
      "queue_summary": {
        "pending_upload": 0,
        "uploaded": 0,
        "processing": 0,
        "failed": 0,
        "ready": 0,
        "stale_processing_locks": 0,
        "oldest_unfinished_created_at": null
      },
      "last_error": null
    },
    "livekit_webhooks": {
      "status": "ok | degraded | stopped",
      "worker_running": true,
      "queue_size": 0,
      "pending_jobs": 0,
      "processing_jobs": 0,
      "failed_jobs": 0,
      "next_due_at": null,
      "last_failed_at": null,
      "last_failure": null
    },
    "membership_expiry_warnings": {
      "status": "ok | degraded | stopped",
      "worker_running": true,
      "poll_interval_seconds": 86400,
      "last_error": null
    }
  },
  "safety": {
    "logs_mcp_enabled": true,
    "log_buffer_max_events": 500
  }
}
```

## VS Code MCP Configuration

Add this server entry to `.vscode/mcp.json` when the backend is running locally on port `8080`:

```json
{
  "servers": {
    "aveli-logs": {
      "type": "http",
      "url": "http://127.0.0.1:8080/mcp/logs"
    }
  }
}
```
