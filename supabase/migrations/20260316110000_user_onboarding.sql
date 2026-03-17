create table if not exists app.user_onboarding (
  user_id uuid primary key references app.profiles(user_id) on delete cascade,
  selected_intro_course_id uuid references app.courses(id) on delete set null,
  profile_completed_at timestamptz,
  onboarding_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_user_onboarding_selected_intro_course
  on app.user_onboarding(selected_intro_course_id);

insert into app.user_onboarding (
  user_id,
  profile_completed_at,
  created_at,
  updated_at
)
select
  p.user_id,
  now(),
  now(),
  now()
from app.profiles p
where coalesce(nullif(trim(p.display_name), ''), '') <> ''
  and coalesce(nullif(trim(p.bio), ''), '') <> ''
  and (p.avatar_media_id is not null or coalesce(nullif(trim(p.photo_url), ''), '') <> '')
on conflict (user_id) do update
set profile_completed_at = coalesce(
      app.user_onboarding.profile_completed_at,
      excluded.profile_completed_at
    ),
    updated_at = now();

with intro_candidates as (
  select
    e.user_id,
    min(e.course_id) as selected_intro_course_id,
    count(distinct e.course_id)::int as intro_course_count
  from app.enrollments e
  join app.courses c
    on c.id = e.course_id
  where c.is_free_intro = true
  group by e.user_id
)
insert into app.user_onboarding (
  user_id,
  selected_intro_course_id,
  created_at,
  updated_at
)
select
  ic.user_id,
  ic.selected_intro_course_id,
  now(),
  now()
from intro_candidates ic
where ic.intro_course_count = 1
on conflict (user_id) do update
set selected_intro_course_id = coalesce(
      app.user_onboarding.selected_intro_course_id,
      excluded.selected_intro_course_id
    ),
    updated_at = now();
