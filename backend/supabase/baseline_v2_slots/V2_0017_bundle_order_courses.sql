create table app.bundle_order_courses (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references app.orders (id),
  bundle_id uuid not null references app.course_bundles (id),
  course_id uuid not null references app.courses (id),
  position integer not null,
  created_at timestamp with time zone not null default now(),
  constraint bundle_order_courses_position_check check (position >= 1),
  constraint bundle_order_courses_order_course_key unique (order_id, course_id),
  constraint bundle_order_courses_order_position_key unique (order_id, position)
);

comment on table app.bundle_order_courses is
  'Immutable order-time snapshot of bundle composition for canonical bundle purchases.';
comment on column app.bundle_order_courses.order_id is
  'Canonical order that owns the immutable bundle purchase snapshot.';
comment on column app.bundle_order_courses.bundle_id is
  'Bundle copied from app.orders.bundle_id at order time.';
comment on column app.bundle_order_courses.course_id is
  'Course included in the purchased bundle at order time.';
comment on column app.bundle_order_courses.position is
  'One-based contiguous order-time bundle course position.';

create index bundle_order_courses_order_id_idx
  on app.bundle_order_courses (order_id);

create index bundle_order_courses_bundle_id_idx
  on app.bundle_order_courses (bundle_id);

create or replace function app.enforce_bundle_order_courses_row_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_order_type app.order_type;
  v_order_bundle_id uuid;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception 'bundle_order_courses rows are immutable';
  end if;

  select o.order_type, o.bundle_id
    into v_order_type, v_order_bundle_id
  from app.orders o
  where o.id = new.order_id
  for key share;

  if not found then
    raise exception 'bundle_order_courses.order_id % does not reference an existing order', new.order_id;
  end if;

  if v_order_type <> 'bundle'::app.order_type then
    raise exception 'bundle_order_courses.order_id % must reference a bundle order', new.order_id;
  end if;

  if v_order_bundle_id is distinct from new.bundle_id then
    raise exception 'bundle_order_courses.bundle_id must match app.orders.bundle_id';
  end if;

  return new;
end;
$$;

create trigger bundle_order_courses_row_contract
before insert or update or delete
on app.bundle_order_courses
for each row
execute function app.enforce_bundle_order_courses_row_contract();

create or replace function app.enforce_bundle_order_courses_contiguous_positions()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_count integer;
  v_min_position integer;
  v_max_position integer;
  v_distinct_positions integer;
begin
  select count(*)::integer,
         min(position)::integer,
         max(position)::integer,
         count(distinct position)::integer
    into v_count, v_min_position, v_max_position, v_distinct_positions
  from app.bundle_order_courses
  where order_id = new.order_id;

  if v_count = 0 then
    return null;
  end if;

  if v_min_position <> 1
     or v_max_position <> v_count
     or v_distinct_positions <> v_count then
    raise exception 'bundle_order_courses positions must be contiguous from 1 for order %', new.order_id;
  end if;

  return null;
end;
$$;

create constraint trigger bundle_order_courses_contiguous_positions
after insert
on app.bundle_order_courses
deferrable initially deferred
for each row
execute function app.enforce_bundle_order_courses_contiguous_positions();
