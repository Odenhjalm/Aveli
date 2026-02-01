-- 20260201133000_teacher_profile_media_home_player_flags.sql
-- Add home player visibility flags for teacher profile media.

begin;

alter table app.teacher_profile_media
  add column if not exists enabled_for_home_player boolean not null default false,
  add column if not exists visibility_intro_material boolean not null default false,
  add column if not exists visibility_course_member boolean not null default false,
  add column if not exists home_visibility_intro_material boolean not null default false,
  add column if not exists home_visibility_course_member boolean not null default false;

commit;

