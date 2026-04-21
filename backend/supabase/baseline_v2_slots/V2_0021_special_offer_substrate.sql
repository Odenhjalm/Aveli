alter type app.media_purpose
  add value if not exists 'special_offer_composite_image';

create table if not exists app.special_offers (
  id uuid not null default gen_random_uuid(),
  teacher_id uuid not null,
  price_amount_cents integer not null,
  state_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint special_offers_pkey primary key (id),
  constraint special_offers_teacher_id_fkey
    foreign key (teacher_id) references app.auth_subjects (user_id),
  constraint special_offers_price_amount_positive_check
    check (price_amount_cents > 0),
  constraint special_offers_state_hash_format_check
    check (state_hash ~ '^[0-9a-f]{64}$')
);

create index if not exists special_offers_teacher_id_idx
  on app.special_offers (teacher_id);

comment on table app.special_offers is
  'Canonical special-offer domain state. Owns teacher binding, price truth, and deterministic state hash only.';

comment on column app.special_offers.price_amount_cents is
  'Canonical special-offer price truth in minor units. No commerce, checkout, payment, or sellability authority lives here.';

comment on column app.special_offers.state_hash is
  'Deterministic SHA-256 over teacher_id, price_amount_cents, and ordered selected courses. Current image exists only when this hash matches the active output hash. No boolean current flags are allowed.';

create table if not exists app.special_offer_courses (
  id uuid not null default gen_random_uuid(),
  special_offer_id uuid not null,
  course_id uuid not null,
  position integer not null,
  constraint special_offer_courses_pkey primary key (id),
  constraint special_offer_courses_special_offer_id_fkey
    foreign key (special_offer_id) references app.special_offers (id) on delete cascade,
  constraint special_offer_courses_course_id_fkey
    foreign key (course_id) references app.courses (id),
  constraint special_offer_courses_offer_course_key
    unique (special_offer_id, course_id),
  constraint special_offer_courses_offer_position_key
    unique (special_offer_id, position),
  constraint special_offer_courses_position_range_check
    check (position between 1 and 5)
);

create index if not exists special_offer_courses_special_offer_id_idx
  on app.special_offer_courses (special_offer_id);

create index if not exists special_offer_courses_course_id_idx
  on app.special_offer_courses (course_id);

comment on table app.special_offer_courses is
  'Canonical selected-course set for a special offer. Defines explicit deterministic ordering and never reuses bundle composition substrate.';

comment on column app.special_offer_courses.position is
  'One-based deterministic course ordering within a special offer. Unique positions in the 1..5 range cap the selected-course set at five rows.';

create or replace function app.compute_special_offer_state_hash(
  p_special_offer_id uuid,
  p_teacher_id uuid,
  p_price_amount_cents integer
)
returns text
language sql
stable
set search_path = pg_catalog, app
as $$
  select encode(
    sha256(
      convert_to(
        format(
          'teacher_id=%s|price_amount_cents=%s|courses=%s',
          p_teacher_id::text,
          p_price_amount_cents::text,
          coalesce(
            (
              select string_agg(
                format('%s:%s', soc.position, soc.course_id::text),
                ',' order by soc.position
              )
              from app.special_offer_courses as soc
              where soc.special_offer_id = p_special_offer_id
            ),
            ''
          )
        ),
        'UTF8'
      )
    ),
    'hex'
  );
$$;

comment on function app.compute_special_offer_state_hash(uuid, uuid, integer) is
  'Canonical special-offer hash function. The hash is derived only from teacher_id, price_amount_cents, and ordered selected courses.';

create or replace function app.apply_special_offer_state_hash()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
begin
  if new.id is null then
    new.id := gen_random_uuid();
  end if;

  if tg_op = 'INSERT' then
    new.created_at := coalesce(new.created_at, clock_timestamp());
  end if;

  new.updated_at := clock_timestamp();
  new.state_hash := app.compute_special_offer_state_hash(
    new.id,
    new.teacher_id,
    new.price_amount_cents
  );

  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'special_offers'
      and tg.tgname = 'special_offers_state_hash_contract'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create trigger special_offers_state_hash_contract
      before insert or update
      on app.special_offers
      for each row
      execute function app.apply_special_offer_state_hash()
    $sql$;
  end if;
end;
$$;

create or replace function app.touch_special_offer_after_course_change()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') and old.special_offer_id is not null then
    update app.special_offers
       set updated_at = clock_timestamp()
     where id = old.special_offer_id;
  end if;

  if tg_op in ('INSERT', 'UPDATE') and new.special_offer_id is not null then
    update app.special_offers
       set updated_at = clock_timestamp()
     where id = new.special_offer_id;
  end if;

  return null;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'special_offer_courses'
      and tg.tgname = 'special_offer_courses_touch_offer_state'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create trigger special_offer_courses_touch_offer_state
      after insert or update or delete
      on app.special_offer_courses
      for each row
      execute function app.touch_special_offer_after_course_change()
    $sql$;
  end if;
end;
$$;

create or replace function app.enforce_special_offer_course_row_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_offer_teacher_id uuid;
  v_course_teacher_id uuid;
begin
  select so.teacher_id, c.teacher_id
    into v_offer_teacher_id, v_course_teacher_id
  from app.special_offers as so
  join app.courses as c
    on c.id = new.course_id
  where so.id = new.special_offer_id;

  if not found then
    raise exception 'special offer course row requires existing offer % and course %',
      new.special_offer_id, new.course_id;
  end if;

  if v_offer_teacher_id is distinct from v_course_teacher_id then
    raise exception 'special-offer courses must belong to the offer teacher';
  end if;

  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'special_offer_courses'
      and tg.tgname = 'special_offer_courses_row_contract'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create trigger special_offer_courses_row_contract
      before insert or update
      on app.special_offer_courses
      for each row
      execute function app.enforce_special_offer_course_row_contract()
    $sql$;
  end if;
end;
$$;

create or replace function app.assert_special_offer_course_set(
  p_special_offer_id uuid
)
returns void
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_teacher_id uuid;
  v_price_amount_cents integer;
  v_state_hash text;
  v_expected_hash text;
  v_course_count integer;
  v_min_position integer;
  v_max_position integer;
  v_distinct_positions integer;
  v_cross_teacher_count integer;
begin
  if p_special_offer_id is null then
    return;
  end if;

  select so.teacher_id,
         so.price_amount_cents,
         so.state_hash,
         count(soc.id)::integer,
         min(soc.position)::integer,
         max(soc.position)::integer,
         count(distinct soc.position)::integer,
         count(*) filter (
           where soc.id is not null
             and c.teacher_id is distinct from so.teacher_id
         )::integer
    into v_teacher_id,
         v_price_amount_cents,
         v_state_hash,
         v_course_count,
         v_min_position,
         v_max_position,
         v_distinct_positions,
         v_cross_teacher_count
  from app.special_offers as so
  left join app.special_offer_courses as soc
    on soc.special_offer_id = so.id
  left join app.courses as c
    on c.id = soc.course_id
  where so.id = p_special_offer_id
  group by so.id, so.teacher_id, so.price_amount_cents, so.state_hash;

  if not found then
    return;
  end if;

  if v_course_count < 1 or v_course_count > 5 then
    raise exception 'special offers require 1..5 selected courses';
  end if;

  if v_min_position <> 1
     or v_max_position <> v_course_count
     or v_distinct_positions <> v_course_count then
    raise exception 'special_offer_courses positions must be contiguous from 1 for offer %',
      p_special_offer_id;
  end if;

  if v_cross_teacher_count > 0 then
    raise exception 'special-offer courses must all belong to the offer teacher';
  end if;

  v_expected_hash := app.compute_special_offer_state_hash(
    p_special_offer_id,
    v_teacher_id,
    v_price_amount_cents
  );

  if v_state_hash is distinct from v_expected_hash then
    raise exception 'special_offer.state_hash must match teacher, price, and ordered selected courses';
  end if;
end;
$$;

create or replace function app.enforce_special_offer_course_set_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
begin
  perform app.assert_special_offer_course_set(new.id);
  return null;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'special_offers'
      and tg.tgname = 'special_offer_course_set_contract'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create constraint trigger special_offer_course_set_contract
      after insert or update
      on app.special_offers
      deferrable initially deferred
      for each row
      execute function app.enforce_special_offer_course_set_contract()
    $sql$;
  end if;
end;
$$;

create table if not exists app.special_offer_composite_image_outputs (
  id uuid not null default gen_random_uuid(),
  special_offer_id uuid not null,
  media_asset_id uuid not null,
  state_hash text not null,
  created_at timestamptz not null default now(),
  constraint special_offer_composite_image_outputs_pkey primary key (id),
  constraint special_offer_composite_image_outputs_special_offer_id_fkey
    foreign key (special_offer_id) references app.special_offers (id) on delete cascade,
  constraint special_offer_composite_image_outputs_media_asset_id_fkey
    foreign key (media_asset_id) references app.media_assets (id),
  constraint special_offer_composite_image_outputs_special_offer_id_key
    unique (special_offer_id),
  constraint special_offer_composite_image_outputs_state_hash_format_check
    check (state_hash ~ '^[0-9a-f]{64}$')
);

create index if not exists special_offer_composite_image_outputs_media_asset_id_idx
  on app.special_offer_composite_image_outputs (media_asset_id);

comment on table app.special_offer_composite_image_outputs is
  'Canonical active special-offer composite-image placement truth. runtime_media must project from this table, never from app.media_assets alone. Projection eligibility requires valid media_asset_id, purpose special_offer_composite_image, and ready state.';

comment on column app.special_offer_composite_image_outputs.state_hash is
  'Offer-state hash captured at successful output binding time. The active image is current only while this hash matches app.special_offers.state_hash.';

create or replace function app.enforce_special_offer_output_asset_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_offer_state_hash text;
  v_media_purpose app.media_purpose;
  v_media_type app.media_type;
  v_media_state app.media_state;
begin
  select so.state_hash,
         ma.purpose,
         ma.media_type,
         ma.state
    into v_offer_state_hash,
         v_media_purpose,
         v_media_type,
         v_media_state
  from app.special_offers as so
  join app.media_assets as ma
    on ma.id = new.media_asset_id
  where so.id = new.special_offer_id;

  if not found then
    raise exception 'special-offer composite output requires existing offer % and media asset %',
      new.special_offer_id, new.media_asset_id;
  end if;

  if v_media_purpose <> 'special_offer_composite_image'::app.media_purpose then
    raise exception 'special-offer composite output media must have purpose special_offer_composite_image';
  end if;

  if v_media_type <> 'image'::app.media_type then
    raise exception 'special-offer composite output media must be image';
  end if;

  if v_media_state <> 'ready'::app.media_state then
    raise exception 'special-offer composite output media must be ready before active binding';
  end if;

  if new.state_hash is distinct from v_offer_state_hash then
    raise exception 'special-offer composite output hash must match the current special-offer state at binding time';
  end if;

  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'special_offer_composite_image_outputs'
      and tg.tgname = 'special_offer_output_asset_contract'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create trigger special_offer_output_asset_contract
      before insert or update
      on app.special_offer_composite_image_outputs
      for each row
      execute function app.enforce_special_offer_output_asset_contract()
    $sql$;
  end if;
end;
$$;

create table if not exists app.special_offer_composite_image_sources (
  id uuid not null default gen_random_uuid(),
  output_id uuid not null,
  source_position integer not null,
  source_course_id uuid not null,
  source_media_asset_id uuid not null,
  constraint special_offer_composite_image_sources_pkey primary key (id),
  constraint special_offer_composite_image_sources_output_id_fkey
    foreign key (output_id) references app.special_offer_composite_image_outputs (id) on delete cascade,
  constraint special_offer_composite_image_sources_source_course_id_fkey
    foreign key (source_course_id) references app.courses (id),
  constraint special_offer_composite_image_sources_source_media_asset_id_fkey
    foreign key (source_media_asset_id) references app.media_assets (id),
  constraint special_offer_composite_image_sources_output_position_key
    unique (output_id, source_position),
  constraint special_offer_composite_image_sources_output_course_key
    unique (output_id, source_course_id),
  constraint special_offer_composite_image_sources_position_range_check
    check (source_position between 1 and 5)
);

create index if not exists special_offer_composite_image_sources_output_id_idx
  on app.special_offer_composite_image_sources (output_id);

create index if not exists special_offer_composite_image_sources_source_course_id_idx
  on app.special_offer_composite_image_sources (source_course_id);

comment on table app.special_offer_composite_image_sources is
  'Canonical persisted source-input set for the active special-offer composite image. Source rows must reflect the exact governed inputs used for generation and must never be inferred later.';

comment on column app.special_offer_composite_image_sources.source_position is
  'One-based deterministic ordering for persisted image-generation inputs.';

create or replace function app.enforce_special_offer_output_source_row_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_special_offer_id uuid;
  v_cover_media_id uuid;
  v_media_purpose app.media_purpose;
  v_media_type app.media_type;
  v_media_state app.media_state;
begin
  select o.special_offer_id
    into v_special_offer_id
  from app.special_offer_composite_image_outputs as o
  where o.id = new.output_id;

  if not found then
    raise exception 'special-offer composite source requires existing output %',
      new.output_id;
  end if;

  if not exists (
    select 1
    from app.special_offer_courses as soc
    where soc.special_offer_id = v_special_offer_id
      and soc.course_id = new.source_course_id
  ) then
    raise exception 'special-offer composite sources must belong to the selected course set';
  end if;

  select c.cover_media_id,
         ma.purpose,
         ma.media_type,
         ma.state
    into v_cover_media_id,
         v_media_purpose,
         v_media_type,
         v_media_state
  from app.courses as c
  join app.media_assets as ma
    on ma.id = new.source_media_asset_id
  where c.id = new.source_course_id;

  if not found then
    raise exception 'special-offer composite source requires existing course % and media asset %',
      new.source_course_id, new.source_media_asset_id;
  end if;

  if v_cover_media_id is distinct from new.source_media_asset_id then
    raise exception 'special-offer composite source media must match app.courses.cover_media_id for the selected source course';
  end if;

  if v_media_purpose <> 'course_cover'::app.media_purpose then
    raise exception 'special-offer composite source media must have purpose course_cover under current accepted authority';
  end if;

  if v_media_type <> 'image'::app.media_type then
    raise exception 'special-offer composite source media must be image';
  end if;

  if v_media_state <> 'ready'::app.media_state then
    raise exception 'special-offer composite source media must be ready';
  end if;

  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'special_offer_composite_image_sources'
      and tg.tgname = 'special_offer_output_source_row_contract'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create trigger special_offer_output_source_row_contract
      before insert or update
      on app.special_offer_composite_image_sources
      for each row
      execute function app.enforce_special_offer_output_source_row_contract()
    $sql$;
  end if;
end;
$$;

create or replace function app.assert_special_offer_output_source_set(
  p_output_id uuid
)
returns void
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_special_offer_id uuid;
  v_output_state_hash text;
  v_offer_state_hash text;
  v_source_count integer;
  v_min_position integer;
  v_max_position integer;
  v_distinct_positions integer;
begin
  if p_output_id is null then
    return;
  end if;

  select o.special_offer_id,
         o.state_hash,
         so.state_hash
    into v_special_offer_id,
         v_output_state_hash,
         v_offer_state_hash
  from app.special_offer_composite_image_outputs as o
  join app.special_offers as so
    on so.id = o.special_offer_id
  where o.id = p_output_id;

  if not found then
    return;
  end if;

  select count(id)::integer,
         min(source_position)::integer,
         max(source_position)::integer,
         count(distinct source_position)::integer
    into v_source_count,
         v_min_position,
         v_max_position,
         v_distinct_positions
  from app.special_offer_composite_image_sources
  where output_id = p_output_id;

  if v_source_count < 1 or v_source_count > 5 then
    raise exception 'special-offer composite outputs require 1..5 persisted source rows';
  end if;

  if v_min_position <> 1
     or v_max_position <> v_source_count
     or v_distinct_positions <> v_source_count then
    raise exception 'special-offer composite source positions must be contiguous from 1 for output %',
      p_output_id;
  end if;

  if v_output_state_hash is distinct from v_offer_state_hash then
    raise exception 'active special-offer composite output hash must match current offer hash at commit time';
  end if;
end;
$$;

create or replace function app.enforce_special_offer_output_source_set_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
begin
  if tg_table_name = 'special_offer_composite_image_outputs' then
    perform app.assert_special_offer_output_source_set(new.id);
    return null;
  end if;

  if tg_op in ('UPDATE', 'DELETE') then
    perform app.assert_special_offer_output_source_set(old.output_id);
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    perform app.assert_special_offer_output_source_set(new.output_id);
  end if;

  return null;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'special_offer_composite_image_outputs'
      and tg.tgname = 'special_offer_output_source_set_contract_on_outputs'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create constraint trigger special_offer_output_source_set_contract_on_outputs
      after insert or update
      on app.special_offer_composite_image_outputs
      deferrable initially deferred
      for each row
      execute function app.enforce_special_offer_output_source_set_contract()
    $sql$;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'special_offer_composite_image_sources'
      and tg.tgname = 'special_offer_output_source_set_contract_on_sources'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create constraint trigger special_offer_output_source_set_contract_on_sources
      after insert or update or delete
      on app.special_offer_composite_image_sources
      deferrable initially deferred
      for each row
      execute function app.enforce_special_offer_output_source_set_contract()
    $sql$;
  end if;
end;
$$;

create table if not exists app.special_offer_composite_image_attempts (
  id uuid not null default gen_random_uuid(),
  special_offer_id uuid not null,
  state_hash text not null,
  status text not null,
  created_at timestamptz not null default now(),
  finished_at timestamptz,
  constraint special_offer_composite_image_attempts_pkey primary key (id),
  constraint special_offer_composite_image_attempts_special_offer_id_fkey
    foreign key (special_offer_id) references app.special_offers (id) on delete cascade,
  constraint special_offer_composite_image_attempts_state_hash_format_check
    check (state_hash ~ '^[0-9a-f]{64}$'),
  constraint special_offer_composite_image_attempts_status_check
    check (status in ('accepted', 'processing', 'succeeded', 'failed')),
  constraint special_offer_composite_image_attempts_finished_at_contract_check
    check (
      (
        status in ('accepted', 'processing')
        and finished_at is null
      )
      or (
        status in ('succeeded', 'failed')
        and finished_at is not null
      )
    )
);

create index if not exists special_offer_composite_image_attempts_special_offer_id_idx
  on app.special_offer_composite_image_attempts (special_offer_id);

create index if not exists special_offer_composite_image_attempts_status_idx
  on app.special_offer_composite_image_attempts (status);

comment on table app.special_offer_composite_image_attempts is
  'Runtime/support attempt tracking for explicit special-offer image generation and regeneration only. Attempts are never active binding truth and failed attempts must not affect the active output.';

comment on column app.special_offer_composite_image_attempts.status is
  'Backend-owned execution support state only. Exact user-facing copy remains under text authority.';

comment on table app.special_offer_composite_image_outputs is
  'Canonical active special-offer composite-image placement truth. No raw URLs, signed URLs, storage paths, or frontend-authored pointers are allowed. runtime_media must later project from this table, not from app.media_assets alone.';
