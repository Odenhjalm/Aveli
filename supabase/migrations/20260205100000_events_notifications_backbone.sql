-- 20260205100000_events_notifications_backbone.sql
-- Backend backbone for events + notification campaigns (distinct from legacy app.notifications).
--
-- Notes:
-- - app.notifications already exists as a legacy per-user inbox (payload/read_at). This migration adds
--   app.notification_campaigns (+ audiences + deliveries) for future async sending.
-- - All timestamps are stored as timestamptz (UTC by convention).

begin;

-- ---------------------------------------------------------------------------
-- Helper: teacher check for RLS (mirrors backend permission logic)
-- ---------------------------------------------------------------------------
create or replace function app.is_teacher(p_user uuid)
returns boolean
language sql
as $$
  select
    app.is_admin(p_user)
    or exists (
      select 1
      from app.profiles p
      where p.user_id = p_user
        and coalesce(p.role_v2, 'user')::text in ('teacher', 'admin')
    )
    or exists (
      select 1
      from app.teacher_permissions tp
      where tp.profile_id = p_user
        and (tp.can_edit_courses = true or tp.can_publish = true)
    )
    or exists (
      select 1
      from app.teacher_approvals ta
      where ta.user_id = p_user
        and ta.approved_at is not null
    );
$$;

-- ---------------------------------------------------------------------------
-- Enumerated types (checked before creation to avoid duplicate errors)
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'event_type'
      and n.nspname = 'app'
  ) then
    create type app.event_type as enum ('ceremony', 'live_class', 'course');
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'event_status'
      and n.nspname = 'app'
  ) then
    create type app.event_status as enum ('draft', 'scheduled', 'live', 'completed', 'cancelled');
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'event_visibility'
      and n.nspname = 'app'
  ) then
    create type app.event_visibility as enum ('public', 'members', 'invited');
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'event_participant_role'
      and n.nspname = 'app'
  ) then
    create type app.event_participant_role as enum ('host', 'participant');
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'event_participant_status'
      and n.nspname = 'app'
  ) then
    create type app.event_participant_status as enum ('registered', 'cancelled', 'attended', 'no_show');
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'notification_type'
      and n.nspname = 'app'
  ) then
    create type app.notification_type as enum ('manual', 'scheduled', 'system');
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'notification_channel'
      and n.nspname = 'app'
  ) then
    create type app.notification_channel as enum ('in_app', 'email');
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'notification_status'
      and n.nspname = 'app'
  ) then
    create type app.notification_status as enum ('pending', 'sent', 'failed');
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'notification_audience_type'
      and n.nspname = 'app'
  ) then
    create type app.notification_audience_type as enum (
      'all_members',
      'event_participants',
      'course_participants',
      'course_members'
    );
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'notification_delivery_status'
      and n.nspname = 'app'
  ) then
    create type app.notification_delivery_status as enum ('pending', 'sent', 'failed');
  end if;
end$$;

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
create table if not exists app.events (
  id uuid primary key default gen_random_uuid(),
  type app.event_type not null,
  title text not null,
  description text,
  image_id uuid references app.media_objects(id) on delete set null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  timezone text not null,
  status app.event_status not null default 'draft',
  visibility app.event_visibility not null default 'invited',
  created_by uuid not null references app.profiles(user_id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint events_end_after_start check (end_at > start_at),
  constraint events_title_not_empty check (length(trim(title)) > 0),
  constraint events_timezone_not_empty check (length(trim(timezone)) > 0)
);

create index if not exists idx_events_start_at on app.events(start_at);
create index if not exists idx_events_created_by on app.events(created_by);
create index if not exists idx_events_status on app.events(status);
create index if not exists idx_events_visibility on app.events(visibility);

create or replace function app.touch_events()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_events_touch on app.events;
create trigger trg_events_touch
before update on app.events
for each row execute function app.touch_events();

create or replace function app.enforce_event_status_progression()
returns trigger
language plpgsql
as $$
declare
  old_rank integer;
  new_rank integer;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.status = new.status then
    return new;
  end if;

  if old.status = 'cancelled' then
    raise exception 'Event status cannot be changed after cancellation';
  end if;

  old_rank := case old.status
    when 'draft' then 1
    when 'scheduled' then 2
    when 'live' then 3
    when 'completed' then 4
    when 'cancelled' then 5
    else null
  end;

  new_rank := case new.status
    when 'draft' then 1
    when 'scheduled' then 2
    when 'live' then 3
    when 'completed' then 4
    when 'cancelled' then 5
    else null
  end;

  if old_rank is null or new_rank is null then
    raise exception 'Invalid event status transition';
  end if;

  -- Cancellation is always allowed as a terminal transition.
  if new.status = 'cancelled' then
    return new;
  end if;

  if old.status = 'completed' then
    raise exception 'Event status cannot be changed after completion';
  end if;

  if new_rank < old_rank then
    raise exception 'Event status cannot move backwards (% -> %)', old.status, new.status;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_events_status_progression on app.events;
create trigger trg_events_status_progression
before update of status on app.events
for each row execute function app.enforce_event_status_progression();

-- ---------------------------------------------------------------------------
-- event_participants
-- ---------------------------------------------------------------------------
create table if not exists app.event_participants (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references app.events(id) on delete cascade,
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  role app.event_participant_role not null default 'participant',
  status app.event_participant_status not null default 'registered',
  registered_at timestamptz not null default now(),
  unique (event_id, user_id)
);

create index if not exists idx_event_participants_event on app.event_participants(event_id);
create index if not exists idx_event_participants_user on app.event_participants(user_id);

-- ---------------------------------------------------------------------------
-- notification_campaigns + audiences + deliveries
-- ---------------------------------------------------------------------------
create table if not exists app.notification_campaigns (
  id uuid primary key default gen_random_uuid(),
  type app.notification_type not null default 'manual',
  channel app.notification_channel not null default 'in_app',
  title text not null,
  body text not null,
  send_at timestamptz not null default now(),
  created_by uuid not null references app.profiles(user_id) on delete cascade,
  status app.notification_status not null default 'pending',
  created_at timestamptz not null default now(),
  constraint notification_campaigns_title_not_empty check (length(trim(title)) > 0),
  constraint notification_campaigns_body_not_empty check (length(trim(body)) > 0)
);

create index if not exists idx_notification_campaigns_created_by on app.notification_campaigns(created_by);
create index if not exists idx_notification_campaigns_send_at on app.notification_campaigns(send_at);
create index if not exists idx_notification_campaigns_status on app.notification_campaigns(status);

create table if not exists app.notification_audiences (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references app.notification_campaigns(id) on delete cascade,
  audience_type app.notification_audience_type not null,
  event_id uuid references app.events(id) on delete cascade,
  course_id uuid references app.courses(id) on delete cascade,
  constraint notification_audiences_target_check check (
    (audience_type = 'all_members' and event_id is null and course_id is null)
    or (audience_type = 'event_participants' and event_id is not null and course_id is null)
    or (audience_type in ('course_participants', 'course_members') and course_id is not null and event_id is null)
  )
);

create index if not exists idx_notification_audiences_notification_id on app.notification_audiences(notification_id);
create index if not exists idx_notification_audiences_event on app.notification_audiences(event_id);
create index if not exists idx_notification_audiences_course on app.notification_audiences(course_id);

create table if not exists app.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references app.notification_campaigns(id) on delete cascade,
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  channel app.notification_channel not null,
  status app.notification_delivery_status not null default 'pending',
  sent_at timestamptz,
  error_message text,
  created_at timestamptz not null default now(),
  unique (notification_id, user_id, channel)
);

create index if not exists idx_notification_deliveries_notification_id on app.notification_deliveries(notification_id);
create index if not exists idx_notification_deliveries_user on app.notification_deliveries(user_id);
create index if not exists idx_notification_deliveries_status on app.notification_deliveries(status);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table app.events enable row level security;
alter table app.event_participants enable row level security;
alter table app.notification_campaigns enable row level security;
alter table app.notification_audiences enable row level security;
alter table app.notification_deliveries enable row level security;

-- Service role full access (consistent baseline) ----------------------------
drop policy if exists events_service_role on app.events;
create policy events_service_role on app.events
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists event_participants_service_role on app.event_participants;
create policy event_participants_service_role on app.event_participants
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists notification_campaigns_service_role on app.notification_campaigns;
create policy notification_campaigns_service_role on app.notification_campaigns
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists notification_audiences_service_role on app.notification_audiences;
create policy notification_audiences_service_role on app.notification_audiences
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists notification_deliveries_service_role on app.notification_deliveries;
create policy notification_deliveries_service_role on app.notification_deliveries
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

-- Events policies -----------------------------------------------------------
drop policy if exists events_read on app.events;
create policy events_read on app.events
  for select to authenticated
  using (
    created_by = auth.uid()
    or app.is_admin(auth.uid())
    or exists (
      select 1
      from app.event_participants ep
      where ep.event_id = id
        and ep.user_id = auth.uid()
        and ep.status <> 'cancelled'
    )
    or (
      status <> 'draft'
      and (
        visibility = 'public'
        or (
          visibility = 'members'
          and exists (
            select 1
            from app.memberships m
            where m.user_id = auth.uid()
              and m.status = 'active'
              and (m.end_date is null or m.end_date > now())
          )
        )
      )
    )
  );

drop policy if exists events_owner_rw on app.events;
create policy events_owner_rw on app.events
  for all to authenticated
  using (
    (created_by = auth.uid() and app.is_teacher(auth.uid()))
    or app.is_admin(auth.uid())
  )
  with check (
    (created_by = auth.uid() and app.is_teacher(auth.uid()))
    or app.is_admin(auth.uid())
  );

-- Event participants policies ----------------------------------------------
drop policy if exists event_participants_read on app.event_participants;
create policy event_participants_read on app.event_participants
  for select to authenticated
  using (
    user_id = auth.uid()
    or app.is_admin(auth.uid())
    or exists (
      select 1
      from app.events e
      where e.id = event_id
        and (e.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
    or exists (
      select 1
      from app.event_participants h
      where h.event_id = event_id
        and h.user_id = auth.uid()
        and h.role = 'host'
        and h.status <> 'cancelled'
    )
  );

drop policy if exists event_participants_insert on app.event_participants;
create policy event_participants_insert on app.event_participants
  for insert to authenticated
  with check (
    app.is_admin(auth.uid())
    or exists (
      select 1
      from app.events e
      where e.id = event_id
        and (e.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
    or (
      user_id = auth.uid()
      and role = 'participant'
    )
  );

drop policy if exists event_participants_write on app.event_participants;
drop policy if exists event_participants_update on app.event_participants;
create policy event_participants_update on app.event_participants
  for update to authenticated
  using (
    app.is_admin(auth.uid())
    or exists (
      select 1
      from app.events e
      where e.id = event_id
        and (e.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
    or exists (
      select 1
      from app.event_participants h
      where h.event_id = event_id
        and h.user_id = auth.uid()
        and h.role = 'host'
        and h.status <> 'cancelled'
    )
  )
  with check (
    app.is_admin(auth.uid())
    or exists (
      select 1
      from app.events e
      where e.id = event_id
        and (e.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
    or exists (
      select 1
      from app.event_participants h
      where h.event_id = event_id
        and h.user_id = auth.uid()
        and h.role = 'host'
        and h.status <> 'cancelled'
    )
  );

drop policy if exists event_participants_delete on app.event_participants;
create policy event_participants_delete on app.event_participants
  for delete to authenticated
  using (
    app.is_admin(auth.uid())
    or exists (
      select 1
      from app.events e
      where e.id = event_id
        and (e.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
    or exists (
      select 1
      from app.event_participants h
      where h.event_id = event_id
        and h.user_id = auth.uid()
        and h.role = 'host'
        and h.status <> 'cancelled'
    )
  );

-- Notification campaign policies -------------------------------------------
drop policy if exists notification_campaigns_owner_rw on app.notification_campaigns;
create policy notification_campaigns_owner_rw on app.notification_campaigns
  for all to authenticated
  using (
    ((created_by = auth.uid()) and app.is_teacher(auth.uid()))
    or app.is_admin(auth.uid())
  )
  with check (
    ((created_by = auth.uid()) and app.is_teacher(auth.uid()))
    or app.is_admin(auth.uid())
  );

drop policy if exists notification_audiences_owner_rw on app.notification_audiences;
create policy notification_audiences_owner_rw on app.notification_audiences
  for all to authenticated
  using (
    exists (
      select 1
      from app.notification_campaigns n
      where n.id = notification_id
        and (
          (n.created_by = auth.uid() and app.is_teacher(auth.uid()))
          or app.is_admin(auth.uid())
        )
    )
  )
  with check (
    exists (
      select 1
      from app.notification_campaigns n
      where n.id = notification_id
        and (
          (n.created_by = auth.uid() and app.is_teacher(auth.uid()))
          or app.is_admin(auth.uid())
        )
    )
  );

drop policy if exists notification_deliveries_read on app.notification_deliveries;
create policy notification_deliveries_read on app.notification_deliveries
  for select to authenticated
  using (
    user_id = auth.uid()
    or app.is_admin(auth.uid())
    or exists (
      select 1
      from app.notification_campaigns n
      where n.id = notification_id
        and (n.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
  );

drop policy if exists notification_deliveries_owner_rw on app.notification_deliveries;
drop policy if exists notification_deliveries_insert on app.notification_deliveries;
create policy notification_deliveries_insert on app.notification_deliveries
  for insert to authenticated
  with check (
    exists (
      select 1
      from app.notification_campaigns n
      where n.id = notification_id
        and (
          (n.created_by = auth.uid() and app.is_teacher(auth.uid()))
          or app.is_admin(auth.uid())
        )
    )
  );

drop policy if exists notification_deliveries_update on app.notification_deliveries;
create policy notification_deliveries_update on app.notification_deliveries
  for update to authenticated
  using (
    exists (
      select 1
      from app.notification_campaigns n
      where n.id = notification_id
        and (
          (n.created_by = auth.uid() and app.is_teacher(auth.uid()))
          or app.is_admin(auth.uid())
        )
    )
  )
  with check (
    exists (
      select 1
      from app.notification_campaigns n
      where n.id = notification_id
        and (
          (n.created_by = auth.uid() and app.is_teacher(auth.uid()))
          or app.is_admin(auth.uid())
        )
    )
  );

drop policy if exists notification_deliveries_delete on app.notification_deliveries;
create policy notification_deliveries_delete on app.notification_deliveries
  for delete to authenticated
  using (
    exists (
      select 1
      from app.notification_campaigns n
      where n.id = notification_id
        and (
          (n.created_by = auth.uid() and app.is_teacher(auth.uid()))
          or app.is_admin(auth.uid())
        )
    )
  );

commit;
