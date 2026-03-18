from __future__ import annotations

from ..db import get_conn


async def sync_home_player_upload_runtime_media(
    *,
    upload_id: str | None = None,
    teacher_id: str | None = None,
) -> int:
    filters: list[str] = []
    params: list[str] = []
    if upload_id is not None:
        filters.append("hpu.id = %s")
        params.append(upload_id)
    if teacher_id is not None:
        filters.append("hpu.teacher_id = %s")
        params.append(teacher_id)

    where_clause = ""
    if filters:
        where_clause = f"WHERE {' AND '.join(filters)}"

    query = f"""
        INSERT INTO app.runtime_media (
          reference_type,
          auth_scope,
          fallback_policy,
          lesson_media_id,
          home_player_upload_id,
          teacher_id,
          course_id,
          lesson_id,
          media_asset_id,
          media_object_id,
          legacy_storage_bucket,
          legacy_storage_path,
          kind,
          active,
          created_at,
          updated_at
        )
        SELECT
          'home_player_upload',
          'home_teacher_library',
          'if_no_ready_asset',
          NULL,
          hpu.id,
          hpu.teacher_id,
          NULL,
          NULL,
          hpu.media_asset_id,
          hpu.media_id,
          CASE
            WHEN nullif(trim(mo.storage_path), '') IS NOT NULL
              THEN coalesce(nullif(trim(mo.storage_bucket), ''), 'course-media')
            ELSE NULL
          END,
          nullif(trim(mo.storage_path), ''),
          CASE lower(coalesce(trim(hpu.kind), 'other'))
            WHEN 'audio' THEN 'audio'
            WHEN 'video' THEN 'video'
            WHEN 'image' THEN 'image'
            WHEN 'pdf' THEN 'document'
            WHEN 'document' THEN 'document'
            ELSE 'other'
          END,
          hpu.active,
          coalesce(hpu.created_at, now()),
          now()
        FROM app.home_player_uploads hpu
        LEFT JOIN app.media_objects mo ON mo.id = hpu.media_id
        {where_clause}
        ON CONFLICT (home_player_upload_id) DO UPDATE
          SET reference_type = excluded.reference_type,
              auth_scope = excluded.auth_scope,
              fallback_policy = excluded.fallback_policy,
              teacher_id = excluded.teacher_id,
              course_id = excluded.course_id,
              lesson_id = excluded.lesson_id,
              media_asset_id = excluded.media_asset_id,
              media_object_id = excluded.media_object_id,
              legacy_storage_bucket = excluded.legacy_storage_bucket,
              legacy_storage_path = excluded.legacy_storage_path,
              kind = excluded.kind,
              active = excluded.active,
              updated_at = now()
    """

    async with get_conn() as cur:
        await cur.execute(query, params)
        return cur.rowcount or 0
