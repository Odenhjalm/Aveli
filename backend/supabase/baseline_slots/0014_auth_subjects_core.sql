create table app.auth_subjects (
  user_id uuid not null,
  onboarding_state text not null,
  role_v2 text not null,
  role text not null,
  is_admin boolean not null,
  constraint auth_subjects_pkey primary key (user_id),
  constraint auth_subjects_onboarding_state_check check (
    onboarding_state in ('incomplete', 'completed')
  ),
  constraint auth_subjects_role_v2_check check (
    role_v2 in ('learner', 'teacher')
  ),
  constraint auth_subjects_role_check check (
    role in ('learner', 'teacher')
  )
);
