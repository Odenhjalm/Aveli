create table app.profiles (
  user_id uuid not null,
  email text not null,
  display_name text,
  role app.profile_role not null default 'student',
  role_v2 app.user_role not null default 'user',
  bio text,
  photo_url text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  avatar_media_id uuid,
  stripe_customer_id text,
  provider_name text,
  provider_user_id text,
  provider_email_verified boolean,
  provider_avatar_url text,
  last_login_provider text,
  last_login_at timestamptz,
  onboarding_state text,
  constraint profiles_pkey primary key (user_id),
  constraint profiles_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade,
  constraint profiles_email_key unique (email),
  constraint profiles_onboarding_state_check
    check (
      onboarding_state is null
      or onboarding_state in (
        'registered_unverified',
        'verified_unpaid',
        'access_active_profile_incomplete',
        'access_active_profile_complete',
        'welcomed'
      )
    )
);

create index profiles_stripe_customer_idx
  on app.profiles (lower(stripe_customer_id));

create index idx_profiles_onboarding_state
  on app.profiles (onboarding_state);

grant select, insert, update on table app.profiles to authenticated, service_role;

alter table app.profiles enable row level security;

drop policy if exists profiles_self_read on app.profiles;
create policy profiles_self_read
on app.profiles
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists profiles_self_insert on app.profiles;
create policy profiles_self_insert
on app.profiles
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists profiles_self_update on app.profiles;
create policy profiles_self_update
on app.profiles
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists profiles_service_role on app.profiles;
create policy profiles_service_role
on app.profiles
for all
to public
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');
