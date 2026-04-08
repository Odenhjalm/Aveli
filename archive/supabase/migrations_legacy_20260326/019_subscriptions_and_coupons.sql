-- 019_subscriptions_and_coupons.sql
-- Add missing subscription/coupon tables and baseline RLS policies.

begin;

-- App-level subscription mirror (legacy fallback).
create table if not exists app.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subscription_id text not null,
  customer_id text,
  price_id text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'subscriptions_subscription_id_key'
      and conrelid = 'app.subscriptions'::regclass
  ) then
    alter table app.subscriptions
      add constraint subscriptions_subscription_id_key unique (subscription_id);
  end if;
end$$;

create index if not exists idx_subscriptions_user on app.subscriptions(user_id);

do $$
begin
  if to_regprocedure('app.set_updated_at()') is not null then
    drop trigger if exists trg_subscriptions_touch on app.subscriptions;
    create trigger trg_subscriptions_touch
      before update on app.subscriptions
      for each row execute function app.set_updated_at();
  end if;
end$$;

-- Public subscription plan catalog + coupons (used by coupon flows).
create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  price_cents integer not null,
  interval text not null check (interval in ('month', 'year')),
  is_active boolean not null default true,
  stripe_product_id text,
  stripe_price_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_subscription_plans_active
  on public.subscription_plans(is_active);

create table if not exists public.coupons (
  code text primary key,
  plan_id uuid references public.subscription_plans(id) on delete set null,
  grants jsonb not null default '{}'::jsonb,
  max_redemptions integer,
  redeemed_count integer not null default 0,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_coupons_plan on public.coupons(plan_id);
create index if not exists idx_coupons_expires on public.coupons(expires_at);

create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id) on delete restrict,
  status text not null default 'active',
  current_period_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_public_subscriptions_user on public.subscriptions(user_id);
create index if not exists idx_public_subscriptions_plan on public.subscriptions(plan_id);

create table if not exists public.user_certifications (
  user_id uuid not null references auth.users(id) on delete cascade,
  area text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, area)
);

create index if not exists idx_user_certifications_area on public.user_certifications(area);

do $$
begin
  if to_regprocedure('app.set_updated_at()') is not null then
    drop trigger if exists trg_subscription_plans_touch on public.subscription_plans;
    create trigger trg_subscription_plans_touch
      before update on public.subscription_plans
      for each row execute function app.set_updated_at();

    drop trigger if exists trg_coupons_touch on public.coupons;
    create trigger trg_coupons_touch
      before update on public.coupons
      for each row execute function app.set_updated_at();

    drop trigger if exists trg_public_subscriptions_touch on public.subscriptions;
    create trigger trg_public_subscriptions_touch
      before update on public.subscriptions
      for each row execute function app.set_updated_at();
  end if;
end$$;

-- RLS for new tables --------------------------------------------------------
alter table app.subscriptions enable row level security;

drop policy if exists subscriptions_service_role on app.subscriptions;
create policy subscriptions_service_role on app.subscriptions
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists subscriptions_self_read on app.subscriptions;
create policy subscriptions_self_read on app.subscriptions
  for select to authenticated
  using (user_id = auth.uid() or app.is_admin(auth.uid()));

alter table public.subscription_plans enable row level security;

drop policy if exists subscription_plans_service_role on public.subscription_plans;
create policy subscription_plans_service_role on public.subscription_plans
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists subscription_plans_public_read on public.subscription_plans;
create policy subscription_plans_public_read on public.subscription_plans
  for select to public
  using (is_active = true);

alter table public.coupons enable row level security;

drop policy if exists coupons_service_role on public.coupons;
create policy coupons_service_role on public.coupons
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table public.subscriptions enable row level security;

drop policy if exists public_subscriptions_service_role on public.subscriptions;
create policy public_subscriptions_service_role on public.subscriptions
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists public_subscriptions_self_read on public.subscriptions;
create policy public_subscriptions_self_read on public.subscriptions
  for select to authenticated
  using (user_id = auth.uid() or app.is_admin(auth.uid()));

alter table public.user_certifications enable row level security;

drop policy if exists user_certifications_service_role on public.user_certifications;
create policy user_certifications_service_role on public.user_certifications
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists user_certifications_self_read on public.user_certifications;
create policy user_certifications_self_read on public.user_certifications
  for select to authenticated
  using (user_id = auth.uid() or app.is_admin(auth.uid()));

-- Ensure service/admin access for course bundles.
do $$
begin
  if to_regclass('app.course_bundles') is not null then
    alter table app.course_bundles enable row level security;

    drop policy if exists course_bundles_service_role on app.course_bundles;
    create policy course_bundles_service_role on app.course_bundles
      for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

    drop policy if exists course_bundles_admin on app.course_bundles;
    create policy course_bundles_admin on app.course_bundles
      for all to authenticated
      using (app.is_admin(auth.uid()))
      with check (app.is_admin(auth.uid()));
  end if;

  if to_regclass('app.course_bundle_courses') is not null then
    alter table app.course_bundle_courses enable row level security;

    drop policy if exists course_bundle_courses_service_role on app.course_bundle_courses;
    create policy course_bundle_courses_service_role on app.course_bundle_courses
      for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

    drop policy if exists course_bundle_courses_admin on app.course_bundle_courses;
    create policy course_bundle_courses_admin on app.course_bundle_courses
      for all to authenticated
      using (app.is_admin(auth.uid()))
      with check (app.is_admin(auth.uid()));
  end if;
end$$;

commit;
