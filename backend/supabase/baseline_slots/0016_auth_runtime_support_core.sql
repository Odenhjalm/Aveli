-- Local canonical auth verification support required by backend auth routes.
-- This slot restores the auth-side persistence surfaces used by local
-- registration/login verification without changing domain logic.

create table app.auth_events (
  id uuid not null default extensions.gen_random_uuid(),
  user_id uuid,
  email text,
  event text not null,
  ip_address inet,
  user_agent text,
  metadata jsonb,
  created_at timestamptz not null default now(),
  constraint auth_events_pkey primary key (id),
  constraint auth_events_user_id_fkey
    foreign key (user_id) references app.profiles (user_id) on delete cascade
);

create index idx_auth_events_created_at
  on app.auth_events (created_at desc);

create index idx_auth_events_user
  on app.auth_events (user_id);

grant select, insert, update, delete on table app.auth_events to authenticated, service_role;

alter table app.auth_events enable row level security;

drop policy if exists auth_events_service on app.auth_events;
create policy auth_events_service
on app.auth_events
for all
to public
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

create table app.refresh_tokens (
  id uuid not null default extensions.gen_random_uuid(),
  user_id uuid not null,
  jti uuid not null,
  token_hash text not null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  rotated_at timestamptz,
  revoked_at timestamptz,
  last_used_at timestamptz,
  constraint refresh_tokens_pkey primary key (id),
  constraint refresh_tokens_jti_key unique (jti),
  constraint refresh_tokens_user_id_fkey
    foreign key (user_id) references app.profiles (user_id) on delete cascade
);

create index idx_refresh_tokens_user
  on app.refresh_tokens (user_id);

grant select, insert, update, delete on table app.refresh_tokens to authenticated, service_role;

alter table app.refresh_tokens enable row level security;

drop policy if exists refresh_tokens_service on app.refresh_tokens;
create policy refresh_tokens_service
on app.refresh_tokens
for all
to public
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

create table app.teacher_approvals (
  id uuid not null default extensions.gen_random_uuid(),
  user_id uuid not null,
  reviewer_id uuid,
  status text not null default 'pending',
  notes text,
  approved_by uuid,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint teacher_approvals_pkey primary key (id),
  constraint teacher_approvals_user_id_key unique (user_id),
  constraint teacher_approvals_user_id_fkey
    foreign key (user_id) references app.profiles (user_id) on delete cascade,
  constraint teacher_approvals_reviewer_id_fkey
    foreign key (reviewer_id) references app.profiles (user_id),
  constraint teacher_approvals_approved_by_fkey
    foreign key (approved_by) references app.profiles (user_id)
);

create index idx_teacher_approvals_user
  on app.teacher_approvals (user_id);

grant select, insert, update, delete on table app.teacher_approvals to authenticated, service_role;

alter table app.teacher_approvals enable row level security;

drop policy if exists teacher_approvals_service on app.teacher_approvals;
create policy teacher_approvals_service
on app.teacher_approvals
for all
to public
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

create table app.teacher_permissions (
  profile_id uuid not null,
  can_edit_courses boolean not null default false,
  can_publish boolean not null default false,
  granted_by uuid,
  granted_at timestamptz not null default now(),
  constraint teacher_permissions_pkey primary key (profile_id),
  constraint teacher_permissions_profile_id_fkey
    foreign key (profile_id) references app.profiles (user_id) on delete cascade,
  constraint teacher_permissions_granted_by_fkey
    foreign key (granted_by) references app.profiles (user_id)
);

grant select, insert, update, delete on table app.teacher_permissions to authenticated, service_role;

alter table app.teacher_permissions enable row level security;

drop policy if exists teacher_meta_service on app.teacher_permissions;
create policy teacher_meta_service
on app.teacher_permissions
for all
to public
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');
