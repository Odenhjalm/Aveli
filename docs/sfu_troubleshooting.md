# SFU / LiveKit – Troubleshooting Guide

This guide collects the most common error patterns for the LiveKit-based live seminars, how to detect them, and recommended fixes. It is meant for support engineers and on-call responders.

## Quick reference

| Symptom | Detection | Likely cause | Resolution |
| ------- | --------- | ------------ | ---------- |
| Token fetch fails in Flutter (`livekit_connect_failed`) | Crashlytics breadcrumb, analytics event | Backend `/sfu/token` returning 4xx/5xx (missing access, session ended, misconfigured LiveKit keys) | Check backend logs (`livekit_connect_failed`). Verify seminar status (`/studio/seminars/{id}`) and LiveKit credentials. |
| Participant stuck connecting | Analytics events show repeated `livekit_room_state` with `connecting` and no `connected` | LiveKit room not created, firewall blocking WS, wrong region | Inspect backend LiveKit REST call logs. Ensure `LIVEKIT_WS_URL` is reachable from client network. |
| Audio/Video drops mid-session | Backend `/metrics` shows increasing `livekit_webhook_retries_total` or failed jobs; Flutter logs `livekit_room_state` toggling | LiveKit webhooks not processed (backend paused). Worker retries or fails. | Check `app.livekit_webhook_jobs` table for stuck jobs. Restart backend (worker drains queue). Investigate LiveKit API availability. |
| Recording missing after session | No `recording_finished` audit; `livekit_webhook_failed_total` increases | LiveKit recording webhook not delivered or failed | Replay payload (if available) or trigger manual recording export via LiveKit dashboard. Ensure webhook secret matches. |
| Crashlytics report `livekit_connect_with_token_failed` | Crashlytics issue with tag `livekit` | Token may be revoked/expired or WS URL invalid | Renew token via backend; ensure device clock is correct (tokens expire). |

## Flutter instrumentation

The mobile client logs key events via:

- `AnalyticsService.logEvent(...)` → Firebase Analytics (and Crashlytics breadcrumb if `crashlyticsBreadcrumb=true`).
- `LoggingService.logInfo/logError(...)` → `dart:developer` (visible in DevTools console).

Important events:

- `livekit_token_fetched`: token request succeeded; contains `seminar_id`.
- `livekit_connect_failed` / `livekit_connect_with_token_failed`: catch and surface connection errors (with Crashlytics breadcrumbs).
- `livekit_room_state`: tracks connection state changes and participant count.
- `livekit_participant_event`: fired when participants join/leave.
- `livekit_disconnect`: emitted when user ends session.

When debugging an issue, retrieve the Crashlytics logs around the reported timestamp and correlate with backend logs for the same seminar/session.

## Backend observability

- Structured JSON logs include `livekit_*` events with `seminar_id`, `session_id`. Search for `livekit_webhook` entries to diagnose processing failures.
- Prometheus metrics on `/metrics`:
  - `livekit_webhook_processed_total`, `livekit_webhook_failed_total`, `livekit_webhook_retries_total`
  - Gauges `livekit_webhook_pending_jobs`, `livekit_webhook_queue_size`
- Health endpoint `/` returns queue summary under `livekit`.
- Database table `app.livekit_webhook_jobs` stores pending/failed payloads. Inspect `last_error` for root cause.

### Replay a failed webhook job

1. Query failed jobs:

   ```sql
   select id, payload, attempt, last_error
   from app.livekit_webhook_jobs
   where status = 'failed';
   ```

2. Requeue by resetting status:

   ```sql
   update app.livekit_webhook_jobs
   set status = 'pending', next_run_at = now(), last_error = null
   where id = '<JOB_ID>';
   ```

3. Verify metrics (`pending_jobs` should increase) and observe logs for processing.

## Common misconfigurations

- **LiveKit credentials missing**: Backend returns 503 (“LiveKit configuration missing”). Sätt `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_WS_URL` **och** `LIVEKIT_API_URL` i `.env`. Restart backend efter uppdatering.
- **Webhook signature mismatch**: Backend logs `Invalid signature`. Ensure `LIVEKIT_WEBHOOK_SECRET` matches LiveKit portal setting.
- **Seminar status**: Attempting to join a `draft` or `ended` seminar results in 409. Hosts must publish and start a session via `/studio/seminars/{id}/sessions/start`.
- **Network restrictions**: Corporate networks may block WebSockets → reproduce via mobile hotspot. Consider fallback instructions for users.

## Support checklist

1. Collect seminar ID, user ID, platform (iOS/Android/Web), approximate time.
2. Pull Crashlytics traces for `livekit_*` breadcrumbs.
3. Check backend metrics/logs for the same window.
4. Validate LiveKit Cloud status (dashboard) for outages.
5. If root cause is backend misconfiguration or LiveKit outage, communicate ETA and mitigation to customer support.
