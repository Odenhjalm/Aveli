begin;

create table if not exists app.educations (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  title text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'educations_slug_key'
       and conrelid = 'app.educations'::regclass
  ) then
    alter table app.educations
      add constraint educations_slug_key unique (slug);
  end if;
end $$;

alter table app.educations enable row level security;

drop policy if exists educations_service_role on app.educations;
create policy educations_service_role on app.educations
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

drop trigger if exists trg_educations_touch on app.educations;
create trigger trg_educations_touch
before update on app.educations
for each row execute function app.set_updated_at();

alter table app.courses
  add column if not exists education_id uuid;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'courses_education_id_fkey'
       and conrelid = 'app.courses'::regclass
  ) then
    alter table app.courses
      add constraint courses_education_id_fkey
      foreign key (education_id) references app.educations(id);
  end if;
end $$;

create index if not exists idx_courses_education_id
  on app.courses (education_id);

commit;
