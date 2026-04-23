alter table app.lesson_contents
  add column if not exists content_document jsonb not null default
    '{"schema_version":"lesson_document_v1","blocks":[]}'::jsonb;

comment on column app.lesson_contents.content_document is
  'Canonical rebuilt-editor lesson document body. The required schema_version is lesson_document_v1.';

drop view if exists app.lesson_content_surface;

create view app.lesson_content_surface
with (security_barrier = true)
as
select
  l.id,
  l.course_id,
  l.lesson_title,
  l.position,
  coalesce(
    lc.content_document,
    '{"schema_version":"lesson_document_v1","blocks":[]}'::jsonb
  ) as content_document,
  lc.content_markdown
from app.lessons as l
left join app.lesson_contents as lc
  on lc.lesson_id = l.id;

comment on view app.lesson_content_surface is
  'Protected lesson content surface. Rebuilt editor content authority is content_document; content_markdown is legacy compatibility only.';
