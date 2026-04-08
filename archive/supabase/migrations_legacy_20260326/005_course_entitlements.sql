-- 005_course_entitlements.sql
-- One-off course purchases (e.g., Vit Magi) entitlements.

begin;

create table if not exists app.course_entitlements (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    course_slug text not null,
    stripe_customer_id text,
    stripe_payment_intent_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists idx_course_entitlements_user_course
on app.course_entitlements (user_id, course_slug);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'course_entitlements_user_course_key'
      and conrelid = 'app.course_entitlements'::regclass
  ) then
    alter table app.course_entitlements
      add constraint course_entitlements_user_course_key unique (user_id, course_slug);
  end if;
end$$;

create or replace function app.touch_course_entitlements()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end; $$ language plpgsql;

drop trigger if exists trg_course_entitlements_touch on app.course_entitlements;

create trigger trg_course_entitlements_touch
before update on app.course_entitlements
for each row execute function app.touch_course_entitlements();

commit;
