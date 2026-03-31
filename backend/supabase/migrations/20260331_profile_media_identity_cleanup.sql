begin;

alter table app.teacher_profile_media
  add column if not exists lesson_media_id uuid,
  add column if not exists seminar_recording_id uuid;

update app.teacher_profile_media
set lesson_media_id = media_id
where media_kind = 'lesson_media'
  and lesson_media_id is null;

update app.teacher_profile_media
set seminar_recording_id = media_id
where media_kind = 'seminar_recording'
  and seminar_recording_id is null;

alter table app.teacher_profile_media
  drop constraint if exists teacher_profile_media_media_id_fkey;

alter table app.teacher_profile_media
  drop constraint if exists teacher_profile_media_teacher_id_media_kind_media_id_key;

drop index if exists app.teacher_profile_media_teacher_id_media_kind_media_id_key;

alter table app.teacher_profile_media
  add constraint teacher_profile_media_lesson_media_id_fkey
  foreign key (lesson_media_id)
  references app.lesson_media(id)
  on delete set null
  not valid;

alter table app.teacher_profile_media
  validate constraint teacher_profile_media_lesson_media_id_fkey;

alter table app.teacher_profile_media
  add constraint teacher_profile_media_seminar_recording_id_fkey
  foreign key (seminar_recording_id)
  references app.seminar_recordings(id)
  on delete set null
  not valid;

alter table app.teacher_profile_media
  validate constraint teacher_profile_media_seminar_recording_id_fkey;

create unique index if not exists teacher_profile_media_teacher_lesson_media_key
  on app.teacher_profile_media (teacher_id, lesson_media_id)
  where lesson_media_id is not null;

create unique index if not exists teacher_profile_media_teacher_seminar_recording_key
  on app.teacher_profile_media (teacher_id, seminar_recording_id)
  where seminar_recording_id is not null;

alter table app.teacher_profile_media
  add constraint teacher_profile_media_identity_check
  check (
    (
      media_kind = 'lesson_media'
      and lesson_media_id is not null
      and seminar_recording_id is null
      and external_url is null
    )
    or (
      media_kind = 'seminar_recording'
      and lesson_media_id is null
      and seminar_recording_id is not null
      and external_url is null
    )
    or (
      media_kind = 'external'
      and lesson_media_id is null
      and seminar_recording_id is null
      and nullif(btrim(external_url), '') is not null
    )
  )
  not valid;

alter table app.teacher_profile_media
  validate constraint teacher_profile_media_identity_check;

alter table app.teacher_profile_media
  drop column if exists media_id,
  drop column if exists metadata,
  drop column if exists visibility_intro_material,
  drop column if exists visibility_course_member,
  drop column if exists home_visibility_intro_material,
  drop column if exists home_visibility_course_member;

commit;
