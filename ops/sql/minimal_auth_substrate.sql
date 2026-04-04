-- Local replay substrate only.
-- This keeps auth as an external dependency while providing the minimum
-- identity surface needed to replay baseline slots against a scratch database.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin;
  end if;
end;
$$;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key default extensions.gen_random_uuid(),
  aud text not null default 'authenticated',
  role text not null default 'authenticated',
  email text,
  encrypted_password text,
  email_confirmed_at timestamptz,
  confirmed_at timestamptz,
  raw_app_meta_data jsonb not null default '{}'::jsonb,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  is_sso_user boolean not null default false,
  is_anonymous boolean not null default false
);

alter table auth.users
  alter column id set default extensions.gen_random_uuid(),
  add column if not exists aud text not null default 'authenticated',
  add column if not exists role text not null default 'authenticated',
  add column if not exists email text,
  add column if not exists encrypted_password text,
  add column if not exists email_confirmed_at timestamptz,
  add column if not exists confirmed_at timestamptz,
  add column if not exists raw_app_meta_data jsonb not null default '{}'::jsonb,
  add column if not exists raw_user_meta_data jsonb not null default '{}'::jsonb,
  add column if not exists created_at timestamptz not null default timezone('utc', now()),
  add column if not exists updated_at timestamptz not null default timezone('utc', now()),
  add column if not exists is_sso_user boolean not null default false,
  add column if not exists is_anonymous boolean not null default false;

create unique index if not exists auth_users_email_ci_key
  on auth.users (lower(email))
  where email is not null;

create or replace function auth.uid()
returns uuid
language sql
stable
as $function$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

create or replace function auth.role()
returns text
language sql
stable
as $function$
  select nullif(current_setting('request.jwt.claim.role', true), '')
$function$;

grant usage on schema auth to public, anon, authenticated, service_role;
grant select on table auth.users to public, anon, authenticated, service_role;
grant execute on function auth.uid() to public, anon, authenticated, service_role;
grant execute on function auth.role() to public, anon, authenticated, service_role;
