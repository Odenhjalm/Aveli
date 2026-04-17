create table app.auth_subjects (
  user_id uuid not null,
  email text,
  role app.auth_subject_role not null,
  onboarding_state app.onboarding_state not null default 'incomplete'::app.onboarding_state,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint auth_subjects_pkey primary key (user_id)
);

create index auth_subjects_onboarding_state_idx
  on app.auth_subjects (onboarding_state);

create index auth_subjects_role_idx
  on app.auth_subjects (role);

comment on table app.auth_subjects is
  'Canonical Aveli auth subject table for identity-bound role and onboarding authority.';

comment on column app.auth_subjects.user_id is
  'Canonical subject identifier aligned to the external auth subject id.';

comment on column app.auth_subjects.email is
  'Optional identity email projection for operator and support context; not credential authority.';

comment on column app.auth_subjects.role is
  'Canonical Aveli role authority for learner, teacher, and admin subjects.';

comment on column app.auth_subjects.onboarding_state is
  'Canonical onboarding progression state: incomplete to welcome_pending to completed.';
