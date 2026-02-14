-- 20260114_91000_backfill_purchases_entitlements.sql
-- Backfill remote-only purchase/claim/entitlements tables.

begin;

-- Purchases -----------------------------------------------------------------
create table if not exists app.purchases (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  order_id uuid,
  stripe_payment_intent text,
  created_at timestamptz not null default now()
);

do $$
begin
  if to_regclass('app.purchases') is null then
    raise notice 'Skipping missing table app.purchases';
  else
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'purchases'
        and column_name = 'id'
    ) then
      alter table app.purchases
        add column id uuid not null default gen_random_uuid();
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'purchases'
        and column_name = 'user_id'
    ) then
      alter table app.purchases
        add column user_id uuid not null;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'purchases'
        and column_name = 'order_id'
    ) then
      alter table app.purchases
        add column order_id uuid;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'purchases'
        and column_name = 'stripe_payment_intent'
    ) then
      alter table app.purchases
        add column stripe_payment_intent text;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'purchases'
        and column_name = 'created_at'
    ) then
      alter table app.purchases
        add column created_at timestamptz not null default now();
    end if;

    if not exists (
      select 1 from pg_constraint
      where conrelid = 'app.purchases'::regclass
        and contype = 'p'
    ) then
      alter table app.purchases
        add constraint purchases_pkey primary key (id);
    end if;

    if not exists (
      select 1 from pg_constraint
      where conname = 'purchases_user_id_fkey'
        and conrelid = 'app.purchases'::regclass
    ) then
      alter table app.purchases
        add constraint purchases_user_id_fkey
        foreign key (user_id) references app.profiles(user_id)
        on delete cascade;
    end if;

    if not exists (
      select 1 from pg_constraint
      where conname = 'purchases_order_id_fkey'
        and conrelid = 'app.purchases'::regclass
    ) then
      alter table app.purchases
        add constraint purchases_order_id_fkey
        foreign key (order_id) references app.orders(id)
        on delete set null;
    end if;

    create index if not exists idx_purchases_user
      on app.purchases (user_id);
    create index if not exists idx_purchases_order
      on app.purchases (order_id);
  end if;
end$$;

-- Course products -----------------------------------------------------------
create table if not exists app.course_products (
  id uuid not null default gen_random_uuid(),
  course_id uuid not null,
  stripe_product_id text not null,
  stripe_price_id text not null,
  price_amount integer not null,
  price_currency text not null default 'sek'::text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  if to_regclass('app.course_products') is null then
    raise notice 'Skipping missing table app.course_products';
  else
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'course_products'
        and column_name = 'id'
    ) then
      alter table app.course_products
        add column id uuid not null default gen_random_uuid();
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'course_products'
        and column_name = 'course_id'
    ) then
      alter table app.course_products
        add column course_id uuid not null;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'course_products'
        and column_name = 'stripe_product_id'
    ) then
      alter table app.course_products
        add column stripe_product_id text not null;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'course_products'
        and column_name = 'stripe_price_id'
    ) then
      alter table app.course_products
        add column stripe_price_id text not null;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'course_products'
        and column_name = 'price_amount'
    ) then
      alter table app.course_products
        add column price_amount integer not null;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'course_products'
        and column_name = 'price_currency'
    ) then
      alter table app.course_products
        add column price_currency text not null default 'sek'::text;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'course_products'
        and column_name = 'is_active'
    ) then
      alter table app.course_products
        add column is_active boolean not null default true;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'course_products'
        and column_name = 'created_at'
    ) then
      alter table app.course_products
        add column created_at timestamptz not null default now();
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'course_products'
        and column_name = 'updated_at'
    ) then
      alter table app.course_products
        add column updated_at timestamptz not null default now();
    end if;

    if not exists (
      select 1 from pg_constraint
      where conrelid = 'app.course_products'::regclass
        and contype = 'p'
    ) then
      alter table app.course_products
        add constraint course_products_pkey primary key (id);
    end if;

    if not exists (
      select 1 from pg_constraint
      where conname = 'course_products_course_id_fkey'
        and conrelid = 'app.course_products'::regclass
    ) then
      alter table app.course_products
        add constraint course_products_course_id_fkey
        foreign key (course_id) references app.courses(id)
        on delete cascade;
    end if;

    create unique index if not exists course_products_course_id_key
      on app.course_products (course_id);
    create index if not exists idx_course_products_course
      on app.course_products (course_id);

    if to_regprocedure('app.set_updated_at()') is null then
      raise notice 'Skipping trigger trg_course_products_updated; missing app.set_updated_at()';
    elsif not exists (
      select 1 from pg_trigger
      where tgname = 'trg_course_products_updated'
        and tgrelid = 'app.course_products'::regclass
    ) then
      create trigger trg_course_products_updated
        before update on app.course_products
        for each row execute function app.set_updated_at();
    end if;
  end if;
end$$;

-- Entitlements --------------------------------------------------------------
create table if not exists app.entitlements (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  course_id uuid not null,
  source text not null,
  stripe_session_id text,
  created_at timestamptz not null default now()
);

do $$
begin
  if to_regclass('app.entitlements') is null then
    raise notice 'Skipping missing table app.entitlements';
  else
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'entitlements'
        and column_name = 'id'
    ) then
      alter table app.entitlements
        add column id uuid not null default gen_random_uuid();
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'entitlements'
        and column_name = 'user_id'
    ) then
      alter table app.entitlements
        add column user_id uuid not null;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'entitlements'
        and column_name = 'course_id'
    ) then
      alter table app.entitlements
        add column course_id uuid not null;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'entitlements'
        and column_name = 'source'
    ) then
      alter table app.entitlements
        add column source text not null;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'entitlements'
        and column_name = 'stripe_session_id'
    ) then
      alter table app.entitlements
        add column stripe_session_id text;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'entitlements'
        and column_name = 'created_at'
    ) then
      alter table app.entitlements
        add column created_at timestamptz not null default now();
    end if;

    if not exists (
      select 1 from pg_constraint
      where conrelid = 'app.entitlements'::regclass
        and contype = 'p'
    ) then
      alter table app.entitlements
        add constraint entitlements_pkey primary key (id);
    end if;

    if not exists (
      select 1 from pg_constraint
      where conname = 'entitlements_user_id_fkey'
        and conrelid = 'app.entitlements'::regclass
    ) then
      alter table app.entitlements
        add constraint entitlements_user_id_fkey
        foreign key (user_id) references app.profiles(user_id)
        on delete cascade;
    end if;

    if not exists (
      select 1 from pg_constraint
      where conname = 'entitlements_course_id_fkey'
        and conrelid = 'app.entitlements'::regclass
    ) then
      alter table app.entitlements
        add constraint entitlements_course_id_fkey
        foreign key (course_id) references app.courses(id)
        on delete cascade;
    end if;

    create index if not exists idx_entitlements_user
      on app.entitlements (user_id);
    create index if not exists idx_entitlements_course
      on app.entitlements (course_id);
    create index if not exists idx_entitlements_user_course
      on app.entitlements (user_id, course_id);
  end if;
end$$;

-- Guest claim tokens --------------------------------------------------------
create table if not exists app.guest_claim_tokens (
  id uuid not null default gen_random_uuid(),
  token text not null,
  purchase_id uuid,
  course_id uuid,
  used boolean not null default false,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

do $$
begin
  if to_regclass('app.guest_claim_tokens') is null then
    raise notice 'Skipping missing table app.guest_claim_tokens';
  else
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'guest_claim_tokens'
        and column_name = 'id'
    ) then
      alter table app.guest_claim_tokens
        add column id uuid not null default gen_random_uuid();
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'guest_claim_tokens'
        and column_name = 'token'
    ) then
      alter table app.guest_claim_tokens
        add column token text not null;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'guest_claim_tokens'
        and column_name = 'purchase_id'
    ) then
      alter table app.guest_claim_tokens
        add column purchase_id uuid;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'guest_claim_tokens'
        and column_name = 'course_id'
    ) then
      alter table app.guest_claim_tokens
        add column course_id uuid;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'guest_claim_tokens'
        and column_name = 'used'
    ) then
      alter table app.guest_claim_tokens
        add column used boolean not null default false;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'guest_claim_tokens'
        and column_name = 'expires_at'
    ) then
      alter table app.guest_claim_tokens
        add column expires_at timestamptz not null;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'app'
        and table_name = 'guest_claim_tokens'
        and column_name = 'created_at'
    ) then
      alter table app.guest_claim_tokens
        add column created_at timestamptz not null default now();
    end if;

    if not exists (
      select 1 from pg_constraint
      where conrelid = 'app.guest_claim_tokens'::regclass
        and contype = 'p'
    ) then
      alter table app.guest_claim_tokens
        add constraint guest_claim_tokens_pkey primary key (id);
    end if;

    if not exists (
      select 1 from pg_constraint
      where conname = 'guest_claim_tokens_purchase_id_fkey'
        and conrelid = 'app.guest_claim_tokens'::regclass
    ) then
      alter table app.guest_claim_tokens
        add constraint guest_claim_tokens_purchase_id_fkey
        foreign key (purchase_id) references app.purchases(id)
        on delete cascade;
    end if;

    if not exists (
      select 1 from pg_constraint
      where conname = 'guest_claim_tokens_course_id_fkey'
        and conrelid = 'app.guest_claim_tokens'::regclass
    ) then
      alter table app.guest_claim_tokens
        add constraint guest_claim_tokens_course_id_fkey
        foreign key (course_id) references app.courses(id)
        on delete set null;
    end if;

    create unique index if not exists guest_claim_tokens_token_key
      on app.guest_claim_tokens (token);
    create index if not exists idx_guest_claim_tokens_expires
      on app.guest_claim_tokens (expires_at);
    create index if not exists idx_guest_claim_tokens_used
      on app.guest_claim_tokens (used);
  end if;
end$$;

commit;
