alter table app.courses
  add column if not exists teacher_id uuid,
  add column if not exists stripe_product_id text,
  add column if not exists active_stripe_price_id text,
  add column if not exists sellable boolean not null default false;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'courses_teacher_id_fkey'
  ) then
    alter table app.courses
      add constraint courses_teacher_id_fkey
      foreign key (teacher_id) references app.auth_subjects (user_id);
  end if;
end
$$;

create index if not exists idx_courses_teacher
  on app.courses (teacher_id);

create unique index if not exists uq_courses_stripe_product_id
  on app.courses (stripe_product_id)
  where stripe_product_id is not null;

create unique index if not exists uq_courses_active_stripe_price_id
  on app.courses (active_stripe_price_id)
  where active_stripe_price_id is not null;

alter table app.course_bundles
  add column if not exists price_amount_cents integer,
  add column if not exists stripe_product_id text,
  add column if not exists active_stripe_price_id text,
  add column if not exists sellable boolean not null default false;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'course_bundles_price_amount_cents_check'
  ) then
    alter table app.course_bundles
      add constraint course_bundles_price_amount_cents_check
      check (
        price_amount_cents is null
        or price_amount_cents > 0
      );
  end if;
end
$$;

create unique index if not exists uq_course_bundles_stripe_product_id
  on app.course_bundles (stripe_product_id)
  where stripe_product_id is not null;

create unique index if not exists uq_course_bundles_active_stripe_price_id
  on app.course_bundles (active_stripe_price_id)
  where active_stripe_price_id is not null;

comment on table app.course_bundles is
  'Canonical bundle identity, ownership, and monetization foundation. Sellability computation and payment logic remain downstream.';
