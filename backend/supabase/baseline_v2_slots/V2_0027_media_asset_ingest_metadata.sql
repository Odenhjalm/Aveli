alter table app.media_assets
  add column original_filename text,
  add column lesson_id uuid,
  add column course_id uuid,
  add column owner_user_id uuid;

create or replace function app.enforce_media_assets_lifecycle_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  in_worker_context boolean :=
    coalesce(current_setting('app.canonical_worker_function_context', true), '') = 'on';
begin
  if new.id is distinct from old.id
     or new.media_type is distinct from old.media_type
     or new.purpose is distinct from old.purpose
     or new.original_filename is distinct from old.original_filename
     or new.lesson_id is distinct from old.lesson_id
     or new.course_id is distinct from old.course_id
     or new.owner_user_id is distinct from old.owner_user_id
     or new.original_object_path is distinct from old.original_object_path
     or new.ingest_format is distinct from old.ingest_format
     or new.created_at is distinct from old.created_at then
    raise exception 'canonical media identity fields are immutable after insert';
  end if;

  if new.state is distinct from old.state
     or new.playback_object_path is distinct from old.playback_object_path
     or new.playback_format is distinct from old.playback_format
     or new.error_message is distinct from old.error_message
     or new.processing_attempts is distinct from old.processing_attempts
     or new.processing_locked_at is distinct from old.processing_locked_at
     or new.next_retry_at is distinct from old.next_retry_at
     or new.updated_at is distinct from old.updated_at then
    if not in_worker_context then
      raise exception 'media lifecycle fields may be mutated only through the canonical worker context';
    end if;
  end if;

  return new;
end;
$$;

comment on column app.media_assets.original_filename is
  'Normalized client-provided filename retained as display metadata only; never canonical storage identity.';

comment on column app.media_assets.lesson_id is
  'Optional immutable ingest ownership metadata for lesson-scoped media assets.';

comment on column app.media_assets.course_id is
  'Optional immutable ingest ownership metadata for course-scoped media assets.';

comment on column app.media_assets.owner_user_id is
  'Optional immutable ingest ownership metadata for user-scoped media assets.';
