create table app.media_pipeline_status (
  media_asset_id uuid not null,
  pipeline_state text not null default 'pending_upload'::text,
  upload_session_id uuid,
  upload_expires_at timestamptz,
  retry_count integer not null default 0,
  max_retries integer not null default 5,
  next_retry_at timestamptz,
  source_wait_reason text,
  source_wait_count integer not null default 0,
  source_wait_deadline_at timestamptz,
  terminal_failure_reason text,
  terminal_at timestamptz,
  reconcile_reason text,
  reconcile_after timestamptz,
  last_transition_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint media_pipeline_status_pkey primary key (media_asset_id),
  constraint media_pipeline_status_media_asset_id_fkey
    foreign key (media_asset_id) references app.media_assets(id) on delete cascade,
  constraint media_pipeline_status_upload_session_id_fkey
    foreign key (upload_session_id) references app.media_upload_sessions(id) on delete set null,
  constraint media_pipeline_status_max_retries_check check (max_retries > 0),
  constraint media_pipeline_status_next_retry_check
    check (pipeline_state <> 'processing_retry_scheduled'::text or next_retry_at is not null),
  constraint media_pipeline_status_pipeline_state_check
    check (pipeline_state = any (array[
      'pending_upload'::text,
      'upload_in_progress'::text,
      'upload_incomplete'::text,
      'upload_orphaned'::text,
      'source_pending'::text,
      'uploaded'::text,
      'processing'::text,
      'processing_waiting_for_source'::text,
      'processing_retry_scheduled'::text,
      'processing_stalled'::text,
      'ready'::text,
      'failed'::text,
      'expired'::text
    ])),
  constraint media_pipeline_status_retry_count_check check (retry_count >= 0),
  constraint media_pipeline_status_retry_lte_max_check check (retry_count <= max_retries),
  constraint media_pipeline_status_source_wait_count_check check (source_wait_count >= 0),
  constraint media_pipeline_status_source_wait_reason_check
    check (
      (pipeline_state <> all (array['source_pending'::text, 'processing_waiting_for_source'::text]))
      or source_wait_reason is not null and btrim(source_wait_reason) <> ''::text
    ),
  constraint media_pipeline_status_terminal_at_check
    check ((pipeline_state = any (array['ready'::text, 'failed'::text, 'expired'::text])) = (terminal_at is not null)),
  constraint media_pipeline_status_terminal_failure_reason_check
    check (
      (pipeline_state <> all (array['failed'::text, 'expired'::text]))
      or terminal_failure_reason is not null and btrim(terminal_failure_reason) <> ''::text
    )
);

create index media_pipeline_status_reconcile_after_idx
  on app.media_pipeline_status (reconcile_after);

create index media_pipeline_status_state_retry_idx
  on app.media_pipeline_status (pipeline_state, next_retry_at);

create index media_pipeline_status_upload_session_idx
  on app.media_pipeline_status (upload_session_id)
  where upload_session_id is not null;

comment on table app.media_pipeline_status is
  'Deterministic media pipeline execution/status table. This table complements app.media_assets.state without replacing canonical media identity or readiness authority.';

comment on column app.media_pipeline_status.pipeline_state is
  'Explicit deterministic media pipeline state used for upload, source wait, retry, stale-lock, terminal, and reconciliation visibility.';

CREATE OR REPLACE FUNCTION app.enforce_media_pipeline_status_transition_contract()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'app'
AS $function$
declare
  v_now timestamptz := clock_timestamp();
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.pipeline_state in ('ready', 'failed', 'expired') then
    raise exception 'terminal media pipeline states are immutable';
  end if;

  if new.pipeline_state = old.pipeline_state then
    new.updated_at := v_now;
    return new;
  end if;

  if not (
    (
      old.pipeline_state = 'pending_upload'
      and new.pipeline_state in (
        'upload_in_progress',
        'upload_orphaned',
        'source_pending',
        'failed',
        'expired'
      )
    )
    or (
      old.pipeline_state = 'upload_in_progress'
      and new.pipeline_state in (
        'upload_incomplete',
        'upload_orphaned',
        'uploaded',
        'failed',
        'expired'
      )
    )
    or (
      old.pipeline_state = 'upload_incomplete'
      and new.pipeline_state in (
        'upload_in_progress',
        'upload_orphaned',
        'failed',
        'expired'
      )
    )
    or (
      old.pipeline_state = 'upload_orphaned'
      and new.pipeline_state in (
        'uploaded',
        'failed',
        'expired'
      )
    )
    or (
      old.pipeline_state = 'source_pending'
      and new.pipeline_state in (
        'upload_in_progress',
        'uploaded',
        'failed',
        'expired'
      )
    )
    or (
      old.pipeline_state = 'uploaded'
      and new.pipeline_state = 'processing'
    )
    or (
      old.pipeline_state = 'processing'
      and new.pipeline_state in (
        'processing_waiting_for_source',
        'processing_retry_scheduled',
        'processing_stalled',
        'ready',
        'failed'
      )
    )
    or (
      old.pipeline_state = 'processing_waiting_for_source'
      and new.pipeline_state in (
        'processing',
        'processing_retry_scheduled',
        'failed'
      )
    )
    or (
      old.pipeline_state = 'processing_retry_scheduled'
      and new.pipeline_state in (
        'processing',
        'failed'
      )
    )
    or (
      old.pipeline_state = 'processing_stalled'
      and new.pipeline_state in (
        'processing_retry_scheduled',
        'failed'
      )
    )
  ) then
    raise exception 'invalid media pipeline transition from % to %',
      old.pipeline_state,
      new.pipeline_state;
  end if;

  new.last_transition_at := v_now;
  new.updated_at := v_now;
  return new;
end;
$function$;

comment on function app.enforce_media_pipeline_status_transition_contract() is
  'DB-level guard for deterministic media pipeline state transitions and terminal-state immutability.';

create trigger media_pipeline_status_transition_contract
before update on app.media_pipeline_status
for each row
execute function app.enforce_media_pipeline_status_transition_contract();
