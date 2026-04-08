begin;

create or replace view app.active_media_inventory as
with storage_meta as (
  select
    o.bucket_id,
    o.name,
    o.created_at as storage_created_at,
    o.updated_at as storage_updated_at,
    nullif(o.metadata ->> 'mimetype', '') as storage_content_type,
    nullif(o.metadata ->> 'size', '')::bigint as storage_size
  from storage.objects o
),
lesson_references as (
  select
    c.id as course_id,
    l.id as lesson_id,
    lm.id as lesson_media_id,
    lm.media_id as media_object_id,
    lm.media_asset_id,
    lower(coalesce(lm.kind, '')) as lesson_media_kind,
    lm.created_at,
    c.is_published as course_is_published,
    l.is_intro as lesson_is_intro,
    true as is_inventory_in_scope,
    true as is_active,
    case
      when lm.media_asset_id is not null then 'media_asset'
      when lm.media_id is not null then 'media_object'
      else 'direct_storage_path'
    end as reference_type,
    nullif(btrim(lm.storage_bucket), '') as lesson_storage_bucket,
    nullif(btrim(lm.storage_path), '') as lesson_storage_path,
    nullif(btrim(mo.storage_bucket), '') as media_object_bucket,
    nullif(btrim(mo.storage_path), '') as media_object_path,
    nullif(btrim(mo.content_type), '') as media_object_content_type,
    mo.byte_size as media_object_byte_size,
    nullif(btrim(mo.original_name), '') as media_object_original_name,
    ma.id as resolved_media_asset_id,
    lower(coalesce(ma.state, '')) as media_asset_state,
    lower(coalesce(ma.media_type, '')) as media_asset_type,
    lower(coalesce(ma.purpose, '')) as media_asset_purpose,
    nullif(btrim(ma.storage_bucket), '') as media_asset_source_bucket,
    nullif(btrim(ma.original_object_path), '') as media_asset_source_path,
    nullif(btrim(ma.original_content_type), '') as media_asset_original_content_type,
    ma.original_size_bytes as media_asset_original_size_bytes,
    nullif(btrim(ma.streaming_storage_bucket), '') as media_asset_stream_bucket,
    nullif(btrim(ma.streaming_object_path), '') as media_asset_stream_path,
    lower(coalesce(ma.ingest_format, '')) as media_asset_ingest_format,
    lower(coalesce(ma.streaming_format, '')) as media_asset_streaming_format,
    nullif(btrim(ma.codec), '') as media_asset_codec,
    nullif(btrim(ma.error_message), '') as media_asset_error_message
  from app.lesson_media lm
  join app.lessons l on l.id = lm.lesson_id
  join app.courses c on c.id = l.course_id
  left join app.media_objects mo on mo.id = lm.media_id
  left join app.media_assets ma on ma.id = lm.media_asset_id
),
canonical_references as (
  select
    lr.*,
    case
      when lr.media_asset_id is not null and lr.media_asset_state = 'ready'
        then coalesce(lr.media_asset_stream_bucket, lr.media_asset_source_bucket, lr.media_object_bucket, lr.lesson_storage_bucket, 'lesson-media')
      when lr.media_asset_id is not null
        then coalesce(lr.media_asset_source_bucket, lr.media_object_bucket, lr.lesson_storage_bucket, 'lesson-media')
      else coalesce(lr.media_object_bucket, lr.lesson_storage_bucket, 'lesson-media')
    end as bucket,
    case
      when lr.media_asset_id is not null and lr.media_asset_state = 'ready'
        then coalesce(lr.media_asset_stream_path, lr.media_asset_source_path, lr.media_object_path, lr.lesson_storage_path)
      when lr.media_asset_id is not null
        then coalesce(lr.media_asset_source_path, lr.media_object_path, lr.lesson_storage_path)
      else coalesce(lr.media_object_path, lr.lesson_storage_path)
    end as storage_path
  from lesson_references lr
)
select
  cr.course_id,
  cr.lesson_id,
  cr.lesson_media_id,
  cr.media_object_id,
  cr.media_asset_id,
  cr.bucket,
  cr.storage_path,
  coalesce(
    case
      when cr.media_asset_id is not null
        and cr.media_asset_state = 'ready'
        and cr.media_asset_type = 'audio'
        then 'audio/mpeg'
      when cr.media_asset_id is not null
        and cr.media_asset_state = 'ready'
        and cr.media_asset_type = 'image'
        then 'image/jpeg'
      else null
    end,
    cr.media_asset_original_content_type,
    cr.media_object_content_type,
    sm.storage_content_type,
    case
      when cr.lesson_media_kind in ('document', 'pdf') then 'application/pdf'
      else null
    end
  ) as content_type,
  coalesce(
    cr.media_object_byte_size,
    cr.media_asset_original_size_bytes,
    sm.storage_size
  ) as byte_size,
  case
    when cr.media_asset_id is not null and cr.media_asset_state <> '' then cr.media_asset_state
    when cr.media_asset_id is null then 'legacy'
    else 'unknown'
  end as media_state,
  cr.created_at,
  cr.reference_type,
  cr.is_inventory_in_scope,
  cr.is_active,
  cr.course_is_published,
  cr.lesson_is_intro,
  cr.lesson_media_kind,
  cr.lesson_storage_bucket,
  cr.lesson_storage_path,
  cr.media_object_bucket,
  cr.media_object_path,
  cr.media_object_content_type,
  cr.media_object_byte_size,
  cr.media_object_original_name,
  cr.media_asset_type,
  cr.media_asset_purpose,
  cr.media_asset_source_bucket,
  cr.media_asset_source_path,
  cr.media_asset_original_content_type,
  cr.media_asset_original_size_bytes,
  cr.media_asset_stream_bucket,
  cr.media_asset_stream_path,
  cr.media_asset_ingest_format,
  cr.media_asset_streaming_format,
  cr.media_asset_codec,
  cr.media_asset_error_message,
  sm.storage_created_at,
  sm.storage_updated_at
from canonical_references cr
left join storage_meta sm
  on sm.bucket_id = cr.bucket
 and sm.name = cr.storage_path;

comment on view app.active_media_inventory is
  'Lesson media inventory for all real course/lesson rows. is_inventory_in_scope and is_active intentionally include unpublished and draft lesson media; publication flags are retained separately for diagnostics.';

commit;
