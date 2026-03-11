begin;

create or replace function app.has_active_membership(p_user uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from app.memberships m
    where m.user_id = p_user
      and m.status in ('active', 'trialing')
      and (m.end_date is null or m.end_date > now())
  );
$$;

alter table app.memberships
  drop constraint if exists memberships_plan_interval_check;

alter table app.memberships
  add constraint memberships_plan_interval_check
  check (plan_interval in ('month', 'year', 'referral'));

create table if not exists app.referral_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  teacher_id uuid not null references app.profiles(user_id) on delete cascade,
  email text not null,
  free_days int,
  free_months int,
  active boolean not null default true,
  redeemed_by_user_id uuid references auth.users(id) on delete set null,
  redeemed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint referral_codes_code_not_empty check (length(trim(code)) > 0),
  constraint referral_codes_email_not_empty check (length(trim(email)) > 0),
  constraint referral_codes_duration_check check (
    (
      free_days is not null
      and free_days > 0
      and free_months is null
    )
    or (
      free_months is not null
      and free_months > 0
      and free_days is null
    )
  )
);

create index if not exists idx_referral_codes_teacher on app.referral_codes(teacher_id);
create index if not exists idx_referral_codes_redeemed_by_user on app.referral_codes(redeemed_by_user_id);
create index if not exists idx_referral_codes_active on app.referral_codes(active);

alter table app.referral_codes enable row level security;

drop policy if exists referral_codes_service_role on app.referral_codes;
create policy referral_codes_service_role on app.referral_codes
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

drop policy if exists referral_codes_teacher_read on app.referral_codes;
create policy referral_codes_teacher_read on app.referral_codes
  for select to authenticated
  using (
    teacher_id = auth.uid()
    or app.is_admin(auth.uid())
  );

drop policy if exists referral_codes_teacher_insert on app.referral_codes;
create policy referral_codes_teacher_insert on app.referral_codes
  for insert to authenticated
  with check (
    teacher_id = auth.uid()
    and app.is_teacher(auth.uid())
  );

drop policy if exists referral_codes_teacher_update on app.referral_codes;
create policy referral_codes_teacher_update on app.referral_codes
  for update to authenticated
  using (
    teacher_id = auth.uid()
    or app.is_admin(auth.uid())
  )
  with check (
    teacher_id = auth.uid()
    or app.is_admin(auth.uid())
  );

commit;
