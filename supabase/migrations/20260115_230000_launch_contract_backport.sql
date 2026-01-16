-- 20260115_230000_launch_contract_backport.sql
-- Backport from launch contract: ensure live_events surfaces exist so legacy replay and db pull do not fail.
-- Idempotent: safe to apply even if remote already contains these tables/policies.
--
-- NOTE: Remote drift safety
-- Remote app.live_events may pre-exist with missing columns (e.g. starts_at/ends_at/is_published).
-- This migration adds missing columns (idempotent) and guards policies/indexes so it remains replay-safe.

begin;

-- ---------------------------------------------------------------------------
-- Live events (DDL)
-- ---------------------------------------------------------------------------
create table if not exists app.live_events (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid references app.profiles(user_id) on delete set null,
  course_id uuid references app.courses(id) on delete set null,
  title text not null,
  description text,
  access_type text not null default 'membership' check (access_type in ('membership','course')),
  starts_at timestamptz,
  ends_at timestamptz,
  livekit_room text,
  metadata jsonb not null default '{}'::jsonb,
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- If remote already has live_events but is missing these columns, add them safely.
alter table app.live_events
  add column if not exists starts_at timestamptz;

alter table app.live_events
  add column if not exists ends_at timestamptz;

alter table app.live_events
  add column if not exists is_published boolean not null default false;

create index if not exists idx_live_events_teacher on app.live_events(teacher_id);
create index if not exists idx_live_events_course on app.live_events(course_id);

-- Create starts_at index only when the column exists (remote drift safety).
do $do$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'app'
      and table_name = 'live_events'
      and column_name = 'starts_at'
  ) then
    execute 'create index if not exists idx_live_events_starts_at on app.live_events(starts_at)';
  else
    raise notice 'Skipping idx_live_events_starts_at: app.live_events.starts_at missing';
  end if;
end
$do$;

-- Add updated_at trigger if helper exists
do $do$
begin
  if to_regprocedure('app.set_updated_at()') is not null then
    execute 'drop trigger if exists trg_live_events_touch on app.live_events';
    execute 'create trigger trg_live_events_touch before update on app.live_events for each row execute function app.set_updated_at()';
  end if;
end
$do$;

-- ---------------------------------------------------------------------------
-- Live event registrations (DDL)
-- ---------------------------------------------------------------------------
create table if not exists app.live_event_registrations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references app.live_events(id) on delete cascade,
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  status text not null default 'registered',
  created_at timestamptz not null default now(),
  unique(event_id, user_id)
);

create index if not exists idx_live_event_registrations_event on app.live_event_registrations(event_id);
create index if not exists idx_live_event_registrations_user on app.live_event_registrations(user_id);

-- ---------------------------------------------------------------------------
-- RLS (enable + policies)
-- ---------------------------------------------------------------------------
alter table app.live_events enable row level security;
alter table app.live_event_registrations enable row level security;

drop policy if exists service_role_full_access on app.live_events;
create policy service_role_full_access on app.live_events
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists service_role_full_access on app.live_event_registrations;
create policy service_role_full_access on app.live_event_registrations
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists live_events_host_rw on app.live_events;
create policy live_events_host_rw on app.live_events
  for all to authenticated
  using (teacher_id = auth.uid() or app.is_admin(auth.uid()))
  with check (teacher_id = auth.uid() or app.is_admin(auth.uid()));

-- live_events_access:
-- Remote drift safety: If is_published column exists, include the published gate.
-- Otherwise, omit it to avoid policy compilation errors during backfill.
drop policy if exists live_events_access on app.live_events;

do $do$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'app'
      and table_name = 'live_events'
      and column_name = 'is_published'
  ) then
    execute $sql$
      create policy live_events_access on app.live_events
        for select to authenticated
        using (
          teacher_id = auth.uid()
          or app.is_admin(auth.uid())
          or (
            is_published = true
            and (
              access_type = 'membership'
              or (
                access_type = 'course'
                and course_id is not null
                and exists (
                  select 1 from app.enrollments e
                  where e.user_id = auth.uid()
                    and e.course_id = live_events.course_id
                )
              )
            )
          )
        )
    $sql$;
  else
    -- Fallback: no is_published column. Still allow course/membership access checks.
    execute $sql$
      create policy live_events_access on app.live_events
        for select to authenticated
        using (
          teacher_id = auth.uid()
          or app.is_admin(auth.uid())
          or (
            access_type = 'membership'
            or (
              access_type = 'course'
              and course_id is not null
              and exists (
                select 1 from app.enrollments e
                where e.user_id = auth.uid()
                  and e.course_id = live_events.course_id
              )
            )
          )
        )
    $sql$;
  end if;
end
$do$;

drop policy if exists live_event_registrations_read on app.live_event_registrations;
create policy live_event_registrations_read on app.live_event_registrations
  for select to authenticated
  using (
    user_id = auth.uid()
    or app.is_admin(auth.uid())
    or exists (
      select 1 from app.live_events e
      where e.id = live_event_registrations.event_id
        and e.teacher_id = auth.uid()
    )
  );

drop policy if exists live_event_registrations_write on app.live_event_registrations;
create policy live_event_registrations_write on app.live_event_registrations
  for all to authenticated
  using (
    user_id = auth.uid()
    or app.is_admin(auth.uid())
    or exists (
      select 1 from app.live_events e
      where e.id = live_event_registrations.event_id
        and e.teacher_id = auth.uid()
    )
  )
  with check (
    user_id = auth.uid()
    or app.is_admin(auth.uid())
    or exists (
      select 1 from app.live_events e
      where e.id = live_event_registrations.event_id
        and e.teacher_id = auth.uid()
    )
  );

commit;
