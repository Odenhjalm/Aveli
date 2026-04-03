create table app.profiles (
  user_id uuid not null,
  email text,
  display_name text,
  avatar_media_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_pkey primary key (user_id),
  constraint profiles_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade,
  constraint profiles_email_key unique (email)
);

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
