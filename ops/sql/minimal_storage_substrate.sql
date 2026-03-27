-- Local scratch verification substrate only.
-- This is not baseline-owned storage schema. It only provides the minimal
-- table surface needed for storage-backed workers to start without errors.

create schema if not exists storage;

create table if not exists storage.buckets (
  id text primary key,
  public boolean not null default false
);

create table if not exists storage.objects (
  id uuid primary key default extensions.gen_random_uuid(),
  bucket_id text not null,
  name text not null
);

create unique index if not exists storage_objects_bucket_name_key
  on storage.objects (bucket_id, name);

insert into storage.buckets (id, public)
values
  ('course-media', false),
  ('lesson-media', false),
  ('public-media', true)
on conflict (id) do nothing;
