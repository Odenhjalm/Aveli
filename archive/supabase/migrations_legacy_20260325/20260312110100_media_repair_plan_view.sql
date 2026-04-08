begin;

create or replace view app.media_repair_plan as
with inventory as (
  select *
  from app.active_media_inventory
),
storage_meta as (
  select
    o.bucket_id,
    o.name,
    o.created_at,
    o.updated_at,
    nullif(o.metadata ->> 'size', '')::bigint as size_bytes
  from storage.objects o
),
normalized_inventory as (
  select
    i.*,
    case
      when i.storage_path is null then null
      when i.storage_path ~* '^https?://'
        then regexp_replace(i.storage_path, '^https?://[^/]+/', '')
      else ltrim(i.storage_path, '/')
    end as url_normalized_path,
    case
      when i.storage_path is null then null
      when ltrim(i.storage_path, '/') like 'storage/v1/object/public/%'
        then regexp_replace(ltrim(i.storage_path, '/'), '^storage/v1/object/public/[^/]+/', '')
      when ltrim(i.storage_path, '/') like 'storage/v1/object/sign/%'
        then regexp_replace(ltrim(i.storage_path, '/'), '^storage/v1/object/sign/[^/]+/', '')
      when ltrim(i.storage_path, '/') like 'object/public/%'
        then regexp_replace(ltrim(i.storage_path, '/'), '^object/public/[^/]+/', '')
      when ltrim(i.storage_path, '/') like 'object/sign/%'
        then regexp_replace(ltrim(i.storage_path, '/'), '^object/sign/[^/]+/', '')
      else null
    end as api_normalized_path
  from inventory i
),
canonicalized as (
  select
    ni.*,
    coalesce(ni.api_normalized_path, ni.url_normalized_path, ni.storage_path) as normalized_storage_path,
    case
      when coalesce(ni.api_normalized_path, ni.url_normalized_path, ni.storage_path) is null then ni.bucket
      when split_part(coalesce(ni.api_normalized_path, ni.url_normalized_path, ni.storage_path), '/', 1) in ('course-media', 'public-media', 'lesson-media', 'seminar-media')
        and split_part(coalesce(ni.api_normalized_path, ni.url_normalized_path, ni.storage_path), '/', 1) <> coalesce(ni.bucket, '')
        then split_part(coalesce(ni.api_normalized_path, ni.url_normalized_path, ni.storage_path), '/', 1)
      else ni.bucket
    end as normalized_bucket
  from normalized_inventory ni
),
normalized_targets as (
  select
    c.*,
    case
      when c.normalized_storage_path is null then null
      when c.normalized_bucket is not null
        and c.normalized_storage_path like c.normalized_bucket || '/%'
        then substring(c.normalized_storage_path from char_length(c.normalized_bucket) + 2)
      when split_part(c.normalized_storage_path, '/', 1) in ('course-media', 'public-media', 'lesson-media', 'seminar-media')
        then regexp_replace(c.normalized_storage_path, '^[^/]+/', '')
      else c.normalized_storage_path
    end as normalized_storage_key
  from canonicalized c
),
storage_checks as (
  select
    nt.*,
    canon.name is not null as canonical_object_exists,
    normalized.name is not null as normalized_object_exists,
    source.name is not null as source_object_exists,
    stream.name is not null as streaming_object_exists,
    coalesce(canon.size_bytes, normalized.size_bytes, source.size_bytes, stream.size_bytes, nt.byte_size) as resolved_byte_size
  from normalized_targets nt
  left join storage_meta canon
    on canon.bucket_id = nt.bucket
   and canon.name = nt.storage_path
  left join storage_meta normalized
    on normalized.bucket_id = nt.normalized_bucket
   and normalized.name = nt.normalized_storage_key
  left join storage_meta source
    on source.bucket_id = nt.media_asset_source_bucket
   and source.name = nt.media_asset_source_path
  left join storage_meta stream
    on stream.bucket_id = coalesce(nt.media_asset_stream_bucket, nt.media_asset_source_bucket)
   and stream.name = nt.media_asset_stream_path
),
legacy_backfill_matches as (
  select
    sc.lesson_media_id,
    case when count(*) = 1 then min(ma.id)::uuid else null end as safe_matching_media_asset_id,
    count(*)::integer as safe_matching_media_asset_count
  from storage_checks sc
  join app.media_assets ma
    on sc.media_asset_id is null
   and ma.lesson_id = sc.lesson_id
   and lower(coalesce(ma.state, '')) = 'ready'
   and (
     (
       coalesce(nullif(ma.streaming_storage_bucket, ''), nullif(ma.storage_bucket, '')) = sc.bucket
       and ma.streaming_object_path = sc.storage_path
     )
     or (
       nullif(ma.storage_bucket, '') = sc.bucket
       and ma.original_object_path = sc.storage_path
     )
     or (
       coalesce(nullif(ma.streaming_storage_bucket, ''), nullif(ma.storage_bucket, '')) = sc.normalized_bucket
       and ma.streaming_object_path = sc.normalized_storage_key
     )
     or (
       nullif(ma.storage_bucket, '') = sc.normalized_bucket
       and ma.original_object_path = sc.normalized_storage_key
     )
   )
  group by sc.lesson_media_id
),
classified as (
  select
    sc.course_id,
    sc.lesson_id,
    sc.lesson_media_id,
    sc.media_object_id,
    sc.media_asset_id,
    sc.bucket,
    sc.storage_path,
    sc.content_type,
    sc.resolved_byte_size as byte_size,
    sc.media_state,
    sc.created_at,
    sc.reference_type,
    sc.is_inventory_in_scope,
    sc.is_active,
    sc.course_is_published,
    sc.lesson_is_intro,
    sc.lesson_media_kind,
    sc.media_asset_type,
    sc.media_asset_purpose,
    sc.media_asset_source_bucket,
    sc.media_asset_source_path,
    sc.media_asset_stream_bucket,
    sc.media_asset_stream_path,
    sc.media_asset_error_message,
    sc.media_asset_ingest_format,
    sc.media_asset_streaming_format,
    sc.normalized_bucket,
    sc.normalized_storage_key as normalized_storage_path,
    sc.canonical_object_exists,
    sc.normalized_object_exists,
    sc.source_object_exists,
    sc.streaming_object_exists,
    coalesce(lbm.safe_matching_media_asset_id, null) as safe_matching_media_asset_id,
    coalesce(lbm.safe_matching_media_asset_count, 0) as safe_matching_media_asset_count,
    (
      sc.storage_path is not null
      and (
        sc.storage_path ~* '^https?://'
        or ltrim(sc.storage_path, '/') like 'storage/v1/object/%'
        or ltrim(sc.storage_path, '/') like 'object/%'
        or (sc.bucket is not null and ltrim(sc.storage_path, '/') like sc.bucket || '/%')
        or split_part(ltrim(sc.storage_path, '/'), '/', 1) in ('course-media', 'public-media', 'lesson-media', 'seminar-media')
      )
    ) as has_invalid_key,
    (
      lower(coalesce(sc.content_type, '')) = 'image/webp'
      or lower(substring(coalesce(sc.storage_path, '') from '\.[^.\/]+$')) = '.webp'
    ) as has_unsupported_format,
    coalesce(sc.resolved_byte_size, 0) > 0 and coalesce(sc.resolved_byte_size, 0) < 100 as has_tiny_file
  from storage_checks sc
  left join legacy_backfill_matches lbm on lbm.lesson_media_id = sc.lesson_media_id
)
select
  c.*,
  case
    when c.has_invalid_key then 'INVALID_KEY'
    when not coalesce(c.canonical_object_exists, false) and not coalesce(c.normalized_object_exists, false) then 'MISSING_IN_STORAGE'
    when c.media_asset_id is not null and lower(coalesce(c.media_state, '')) <> 'ready' then 'NOT_READY_ASSET'
    when c.has_unsupported_format then 'UNSUPPORTED_FORMAT'
    when c.has_tiny_file then 'TINY_FILE'
    when c.media_asset_id is null then 'LEGACY_DIRECT_REFERENCE'
    else null
  end as issue_type,
  case
    when c.has_invalid_key then 'REKEY_STORAGE_PATH'
    when not coalesce(c.canonical_object_exists, false) and not coalesce(c.normalized_object_exists, false) then
      case
        when c.media_asset_id is not null and c.source_object_exists then 'RESTORE_FROM_SOURCE'
        when c.media_asset_id is null and c.safe_matching_media_asset_count = 1 then 'BACKFILL_MEDIA_ASSET'
        else 'MANUAL_REUPLOAD_REQUIRED'
      end
    when c.media_asset_id is not null and lower(coalesce(c.media_state, '')) <> 'ready' then
      case
        when c.source_object_exists then 'RESTORE_FROM_SOURCE'
        else 'MANUAL_REUPLOAD_REQUIRED'
      end
    when c.has_unsupported_format then
      case
        when c.media_asset_id is null and c.safe_matching_media_asset_count = 1 then 'BACKFILL_MEDIA_ASSET'
        when coalesce(c.canonical_object_exists, false) or coalesce(c.normalized_object_exists, false) or c.source_object_exists then 'TRANSCODE_FORMAT'
        else 'MANUAL_REUPLOAD_REQUIRED'
      end
    when c.has_tiny_file then
      case
        when c.media_asset_id is not null and c.source_object_exists then 'RESTORE_FROM_SOURCE'
        when c.media_asset_id is null and c.safe_matching_media_asset_count = 1 then 'BACKFILL_MEDIA_ASSET'
        else 'MANUAL_REUPLOAD_REQUIRED'
      end
    when c.media_asset_id is null then
      case
        when c.safe_matching_media_asset_count = 1 then 'BACKFILL_MEDIA_ASSET'
        else 'NO_ACTION'
      end
    else 'NO_ACTION'
  end as fix_strategy,
  (
    case
      when c.is_inventory_in_scope then 0 else 500
    end
    + case
      when c.has_invalid_key then 10
      when not coalesce(c.canonical_object_exists, false) and not coalesce(c.normalized_object_exists, false) then 20
      when c.media_asset_id is not null and lower(coalesce(c.media_state, '')) <> 'ready' then 30
      when c.has_unsupported_format then 40
      when c.has_tiny_file then 50
      when c.media_asset_id is null then 60
      else 900
    end
    + case
      when c.reference_type = 'media_asset' then 0
      when c.reference_type = 'media_object' then 5
      else 10
    end
  ) as repair_priority
from classified c;

comment on view app.media_repair_plan is
  'Classification layer for active_media_inventory. Produces idempotent repair strategies without deleting any media.';

commit;
