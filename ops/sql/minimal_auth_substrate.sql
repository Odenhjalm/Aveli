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
create extension if not exists "uuid-ossp" with schema extensions;

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key,
  email text,
  encrypted_password text,
  email_confirmed_at timestamp with time zone,
  confirmed_at timestamp with time zone,
  raw_app_meta_data jsonb not null default '{}'::jsonb,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

alter table auth.users
  add column if not exists encrypted_password text;

alter table auth.users
  add column if not exists email_confirmed_at timestamp with time zone;

alter table auth.users
  add column if not exists confirmed_at timestamp with time zone;

alter table auth.users
  add column if not exists raw_app_meta_data jsonb not null default '{}'::jsonb;

alter table auth.users
  add column if not exists raw_user_meta_data jsonb not null default '{}'::jsonb;

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
