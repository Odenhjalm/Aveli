do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'app'
      and t.typname = 'order_status'
  ) then
    create type "app"."order_status" as enum (
      'pending',
      'requires_action',
      'processing',
      'paid',
      'canceled',
      'failed',
      'refunded'
    );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'app'
      and t.typname = 'order_type'
  ) then
    create type "app"."order_type" as enum (
      'one_off',
      'subscription',
      'bundle'
    );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'app'
      and t.typname = 'payment_status'
  ) then
    create type "app"."payment_status" as enum (
      'pending',
      'processing',
      'paid',
      'failed',
      'refunded'
    );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'app'
      and t.typname = 'service_status'
  ) then
    create type "app"."service_status" as enum (
      'draft',
      'active',
      'paused',
      'archived'
    );
  end if;
end
$$;

create table if not exists "app"."billing_logs" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid,
  "step" text,
  "info" jsonb not null default '{}'::jsonb,
  "created_at" timestamp with time zone not null default now()
);

alter table "app"."billing_logs" enable row level security;

create table if not exists "app"."memberships" (
  "membership_id" uuid not null default gen_random_uuid(),
  "user_id" uuid not null,
  "plan_interval" text not null,
  "price_id" text not null,
  "stripe_customer_id" text,
  "stripe_subscription_id" text,
  "start_date" timestamp with time zone not null default now(),
  "end_date" timestamp with time zone,
  "status" text not null default 'active'::text,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now()
);

alter table "app"."memberships" enable row level security;

create table if not exists "app"."services" (
  "id" uuid not null default gen_random_uuid(),
  "provider_id" uuid not null,
  "title" text not null,
  "description" text,
  "status" app.service_status not null default 'draft'::app.service_status,
  "price_cents" integer not null default 0,
  "currency" text not null default 'sek'::text,
  "duration_min" integer,
  "requires_certification" boolean not null default false,
  "certified_area" text,
  "thumbnail_url" text,
  "active" boolean not null default true,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now()
);

alter table "app"."services" enable row level security;

create table if not exists "app"."orders" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid not null,
  "course_id" uuid,
  "service_id" uuid,
  "amount_cents" integer not null,
  "currency" text not null default 'sek'::text,
  "status" app.order_status not null default 'pending'::app.order_status,
  "stripe_checkout_id" text,
  "stripe_payment_intent" text,
  "metadata" jsonb not null default '{}'::jsonb,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "order_type" app.order_type not null default 'one_off'::app.order_type,
  "session_id" uuid,
  "session_slot_id" uuid,
  "stripe_subscription_id" text,
  "connected_account_id" text,
  "stripe_customer_id" text
);

alter table "app"."orders" enable row level security;

create table if not exists "app"."payment_events" (
  "id" uuid not null default gen_random_uuid(),
  "event_id" text not null,
  "payload" jsonb not null,
  "processed_at" timestamp with time zone default now()
);

alter table "app"."payment_events" enable row level security;

create table if not exists "app"."payments" (
  "id" uuid not null default gen_random_uuid(),
  "order_id" uuid not null,
  "provider" text not null,
  "provider_reference" text,
  "status" app.payment_status not null default 'pending'::app.payment_status,
  "amount_cents" integer not null,
  "currency" text not null default 'sek'::text,
  "metadata" jsonb not null default '{}'::jsonb,
  "raw_payload" jsonb,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now()
);

alter table "app"."payments" enable row level security;

create table if not exists "app"."referral_codes" (
  "id" uuid not null default gen_random_uuid(),
  "code" text not null,
  "teacher_id" uuid not null,
  "email" text not null,
  "free_days" integer,
  "free_months" integer,
  "active" boolean not null default true,
  "redeemed_by_user_id" uuid,
  "redeemed_at" timestamp with time zone,
  "created_at" timestamp with time zone not null default now()
);

create table if not exists "app"."stripe_customers" (
  "user_id" uuid not null,
  "customer_id" text not null,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now()
);

alter table "app"."stripe_customers" enable row level security;

create unique index if not exists "billing_logs_pkey"
  on "app"."billing_logs" using btree ("id");

create index if not exists "idx_billing_logs_user_created"
  on "app"."billing_logs" using btree ("user_id", "created_at" desc);

create index if not exists "idx_billing_logs_step_created"
  on "app"."billing_logs" using btree ("step", "created_at" desc);

create unique index if not exists "memberships_pkey"
  on "app"."memberships" using btree ("membership_id");

create unique index if not exists "memberships_user_id_key"
  on "app"."memberships" using btree ("user_id");

create index if not exists "idx_memberships_stripe_customer"
  on "app"."memberships" using btree ("stripe_customer_id");

create index if not exists "idx_memberships_stripe_subscription"
  on "app"."memberships" using btree ("stripe_subscription_id");

create unique index if not exists "services_pkey"
  on "app"."services" using btree ("id");

create index if not exists "idx_services_provider"
  on "app"."services" using btree ("provider_id");

create index if not exists "idx_services_status"
  on "app"."services" using btree ("status");

create unique index if not exists "orders_pkey"
  on "app"."orders" using btree ("id");

create index if not exists "idx_orders_connected_account"
  on "app"."orders" using btree ("connected_account_id");

create index if not exists "idx_orders_course"
  on "app"."orders" using btree ("course_id");

create index if not exists "idx_orders_service"
  on "app"."orders" using btree ("service_id");

create index if not exists "idx_orders_status"
  on "app"."orders" using btree ("status");

create index if not exists "idx_orders_user"
  on "app"."orders" using btree ("user_id");

create unique index if not exists "payment_events_pkey"
  on "app"."payment_events" using btree ("id");

create unique index if not exists "payment_events_event_id_key"
  on "app"."payment_events" using btree ("event_id");

create unique index if not exists "payments_pkey"
  on "app"."payments" using btree ("id");

create index if not exists "idx_payments_order"
  on "app"."payments" using btree ("order_id");

create index if not exists "idx_payments_status"
  on "app"."payments" using btree ("status");

create unique index if not exists "referral_codes_pkey"
  on "app"."referral_codes" using btree ("id");

create unique index if not exists "referral_codes_code_key"
  on "app"."referral_codes" using btree ("code");

create unique index if not exists "stripe_customers_pkey"
  on "app"."stripe_customers" using btree ("user_id");

create index if not exists "idx_stripe_customers_customer"
  on "app"."stripe_customers" using btree ("customer_id");

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'billing_logs_pkey') then
    alter table "app"."billing_logs"
      add constraint "billing_logs_pkey" primary key using index "billing_logs_pkey";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'memberships_pkey') then
    alter table "app"."memberships"
      add constraint "memberships_pkey" primary key using index "memberships_pkey";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'memberships_user_id_key') then
    alter table "app"."memberships"
      add constraint "memberships_user_id_key" unique using index "memberships_user_id_key";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'memberships_user_id_fkey') then
    alter table "app"."memberships"
      add constraint "memberships_user_id_fkey"
      foreign key ("user_id") references "auth"."users" ("id") on delete cascade not valid;
    alter table "app"."memberships"
      validate constraint "memberships_user_id_fkey";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'services_pkey') then
    alter table "app"."services"
      add constraint "services_pkey" primary key using index "services_pkey";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'services_provider_id_fkey') then
    alter table "app"."services"
      add constraint "services_provider_id_fkey"
      foreign key ("provider_id") references "app"."profiles" ("user_id") on delete cascade not valid;
    alter table "app"."services"
      validate constraint "services_provider_id_fkey";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'orders_pkey') then
    alter table "app"."orders"
      add constraint "orders_pkey" primary key using index "orders_pkey";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'orders_user_id_fkey') then
    alter table "app"."orders"
      add constraint "orders_user_id_fkey"
      foreign key ("user_id") references "app"."profiles" ("user_id") on delete cascade not valid;
    alter table "app"."orders"
      validate constraint "orders_user_id_fkey";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'orders_course_id_fkey') then
    alter table "app"."orders"
      add constraint "orders_course_id_fkey"
      foreign key ("course_id") references "app"."courses" ("id") on delete set null not valid;
    alter table "app"."orders"
      validate constraint "orders_course_id_fkey";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'orders_service_id_fkey') then
    alter table "app"."orders"
      add constraint "orders_service_id_fkey"
      foreign key ("service_id") references "app"."services" ("id") on delete set null not valid;
    alter table "app"."orders"
      validate constraint "orders_service_id_fkey";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'payment_events_pkey') then
    alter table "app"."payment_events"
      add constraint "payment_events_pkey" primary key using index "payment_events_pkey";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'payment_events_event_id_key') then
    alter table "app"."payment_events"
      add constraint "payment_events_event_id_key" unique using index "payment_events_event_id_key";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'payments_pkey') then
    alter table "app"."payments"
      add constraint "payments_pkey" primary key using index "payments_pkey";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'payments_order_id_fkey') then
    alter table "app"."payments"
      add constraint "payments_order_id_fkey"
      foreign key ("order_id") references "app"."orders" ("id") on delete cascade not valid;
    alter table "app"."payments"
      validate constraint "payments_order_id_fkey";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'referral_codes_pkey') then
    alter table "app"."referral_codes"
      add constraint "referral_codes_pkey" primary key using index "referral_codes_pkey";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'referral_codes_code_key') then
    alter table "app"."referral_codes"
      add constraint "referral_codes_code_key" unique using index "referral_codes_code_key";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'stripe_customers_pkey') then
    alter table "app"."stripe_customers"
      add constraint "stripe_customers_pkey" primary key using index "stripe_customers_pkey";
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'stripe_customers_user_id_fkey') then
    alter table "app"."stripe_customers"
      add constraint "stripe_customers_user_id_fkey"
      foreign key ("user_id") references "app"."profiles" ("user_id") on delete cascade not valid;
    alter table "app"."stripe_customers"
      validate constraint "stripe_customers_user_id_fkey";
  end if;
end
$$;
