-- Local scratch verification substrate only.
-- This is not baseline-owned storage schema. It only provides the minimal
-- table surface needed for storage-backed workers to start without errors.

create schema if not exists storage;

create table if not exists storage.buckets (
  id text primary key,
  name text,
  public boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table storage.buckets
  add column if not exists name text,
  add column if not exists public boolean not null default false,
  add column if not exists created_at timestamptz not null default timezone('utc', now()),
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

update storage.buckets
   set name = id
 where name is null;

alter table storage.buckets
  alter column name set not null;

create table if not exists storage.objects (
  id uuid primary key default extensions.gen_random_uuid(),
  bucket_id text not null,
  name text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  last_accessed_at timestamptz
);

alter table storage.objects
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists created_at timestamptz not null default timezone('utc', now()),
  add column if not exists updated_at timestamptz not null default timezone('utc', now()),
  add column if not exists last_accessed_at timestamptz;

create unique index if not exists storage_objects_bucket_name_key
  on storage.objects (bucket_id, name);

insert into storage.buckets (id, name, public)
values
  ('course-media', 'course-media', false),
  ('lesson-media', 'lesson-media', false),
  ('profile-media', 'profile-media', false),
  ('public-media', 'public-media', true)
on conflict (id) do nothing;
