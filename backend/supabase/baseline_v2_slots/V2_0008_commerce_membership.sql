create table app.memberships (
  membership_id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  status app.membership_status not null,
  source app.membership_source not null,
  effective_at timestamptz,
  expires_at timestamptz,
  canceled_at timestamptz,
  ended_at timestamptz,
  provider_customer_id text,
  provider_subscription_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint memberships_pkey primary key (membership_id),
  constraint memberships_user_id_key unique (user_id),
  constraint memberships_user_id_fkey
    foreign key (user_id) references app.auth_subjects (user_id),
  constraint memberships_referral_expires_at_check
    check (
      source <> 'referral'::app.membership_source
      or expires_at is not null
    ),
  constraint memberships_canceled_requires_expires_check
    check (
      status <> 'canceled'::app.membership_status
      or expires_at is not null
    )
);

create index memberships_status_idx
  on app.memberships (status);

create index memberships_app_entry_idx
  on app.memberships (user_id, status, expires_at);

comment on table app.memberships is
  'Canonical app-entry membership state. Independent from orders and payments.';

create table app.course_bundles (
  id uuid not null default gen_random_uuid(),
  teacher_id uuid not null,
  title text not null,
  price_amount_cents integer,
  stripe_product_id text,
  active_stripe_price_id text,
  sellable boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint course_bundles_pkey primary key (id),
  constraint course_bundles_teacher_id_fkey
    foreign key (teacher_id) references app.auth_subjects (user_id),
  constraint course_bundles_title_not_blank_check
    check (btrim(title) <> ''),
  constraint course_bundles_price_positive_check
    check (price_amount_cents is null or price_amount_cents > 0),
  constraint course_bundles_sellable_requires_commerce_check
    check (
      sellable = false
      or (
        price_amount_cents is not null
        and stripe_product_id is not null
        and btrim(stripe_product_id) <> ''
        and active_stripe_price_id is not null
        and btrim(active_stripe_price_id) <> ''
      )
    )
);

create index course_bundles_teacher_id_idx
  on app.course_bundles (teacher_id);

create unique index course_bundles_stripe_product_id_key
  on app.course_bundles (stripe_product_id)
  where stripe_product_id is not null;

create unique index course_bundles_active_stripe_price_id_key
  on app.course_bundles (active_stripe_price_id)
  where active_stripe_price_id is not null;

comment on table app.course_bundles is
  'Canonical bundle entity for grouping courses in commerce flows.';

create table app.course_bundle_courses (
  bundle_id uuid not null,
  course_id uuid not null,
  position integer not null,
  constraint course_bundle_courses_pkey primary key (bundle_id, course_id),
  constraint course_bundle_courses_bundle_id_fkey
    foreign key (bundle_id) references app.course_bundles (id) on delete cascade,
  constraint course_bundle_courses_course_id_fkey
    foreign key (course_id) references app.courses (id) on delete cascade,
  constraint course_bundle_courses_position_check check (position >= 1),
  constraint course_bundle_courses_position_unique unique (bundle_id, position)
);

comment on table app.course_bundle_courses is
  'Defines course composition inside a bundle.';

create or replace function app.enforce_course_bundle_same_teacher()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_bundle_teacher uuid;
  v_course_teacher uuid;
begin
  select teacher_id into v_bundle_teacher
  from app.course_bundles
  where id = new.bundle_id;

  select teacher_id into v_course_teacher
  from app.courses
  where id = new.course_id;

  if v_bundle_teacher is distinct from v_course_teacher then
    raise exception 'bundle courses must belong to same teacher';
  end if;

  return new;
end;
$$;

create trigger course_bundle_same_teacher
before insert or update on app.course_bundle_courses
for each row
execute function app.enforce_course_bundle_same_teacher();

create table app.orders (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  course_id uuid,
  bundle_id uuid,
  order_type app.order_type not null default 'one_off'::app.order_type,
  amount_cents integer not null,
  currency text not null default 'sek'::text,
  status app.order_status not null default 'pending'::app.order_status,
  stripe_checkout_id text,
  stripe_payment_intent text,
  stripe_subscription_id text,
  stripe_customer_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint orders_pkey primary key (id),
  constraint orders_user_id_fkey
    foreign key (user_id) references app.auth_subjects (user_id),
  constraint orders_course_id_fkey
    foreign key (course_id) references app.courses (id),
  constraint orders_bundle_id_fkey
    foreign key (bundle_id) references app.course_bundles (id),
  constraint orders_amount_positive_check check (amount_cents > 0),
  constraint orders_currency_check
    check (currency = lower(currency) and length(currency) = 3),
  constraint orders_target_by_type_check
    check (
      (
        order_type = 'one_off'::app.order_type
        and course_id is not null
        and bundle_id is null
      )
      or (
        order_type = 'bundle'::app.order_type
        and bundle_id is not null
        and course_id is null
      )
      or (
        order_type = 'subscription'::app.order_type
        and course_id is null
        and bundle_id is null
      )
    )
);

create index orders_user_id_idx
  on app.orders (user_id);

create index orders_status_idx
  on app.orders (status);

comment on table app.orders is
  'Canonical purchase identity. Does not grant access directly.';

create table app.payments (
  id uuid not null default gen_random_uuid(),
  order_id uuid not null,
  provider text not null,
  provider_reference text,
  status app.payment_status not null default 'pending'::app.payment_status,
  amount_cents integer not null,
  currency text not null default 'sek'::text,
  metadata jsonb not null default '{}'::jsonb,
  raw_payload jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payments_pkey primary key (id),
  constraint payments_order_id_fkey
    foreign key (order_id) references app.orders (id) on delete cascade,
  constraint payments_provider_not_blank_check check (btrim(provider) <> ''),
  constraint payments_amount_positive_check check (amount_cents > 0),
  constraint payments_currency_check
    check (currency = lower(currency) and length(currency) = 3)
);

create index payments_order_id_idx
  on app.payments (order_id);

create index payments_status_idx
  on app.payments (status);

comment on table app.payments is
  'Canonical payment settlement records. No domain authority beyond payment status.';
