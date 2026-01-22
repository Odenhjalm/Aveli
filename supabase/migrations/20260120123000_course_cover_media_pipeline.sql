alter table app.media_assets
  add column if not exists purpose text not null default 'lesson_audio';

alter table app.media_assets
  add column if not exists streaming_storage_bucket text;

alter table app.media_assets
  drop constraint if exists media_assets_media_type_check;

alter table app.media_assets
  add constraint media_assets_media_type_check
    check (media_type in ('audio', 'image'));

alter table app.media_assets
  drop constraint if exists media_assets_purpose_check;

alter table app.media_assets
  add constraint media_assets_purpose_check
    check (purpose in ('lesson_audio', 'course_cover'));

create index if not exists idx_media_assets_purpose
  on app.media_assets(purpose);

create index if not exists idx_media_assets_course_cover
  on app.media_assets(course_id)
  where purpose = 'course_cover';

alter table app.courses
  add column if not exists cover_media_id uuid
    references app.media_assets(id) on delete set null;

create index if not exists idx_courses_cover_media
  on app.courses(cover_media_id);
