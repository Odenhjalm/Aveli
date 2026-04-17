create table app.courses (
  id uuid not null default gen_random_uuid(),
  teacher_id uuid not null,
  title text not null,
  slug text not null,
  course_group_id uuid not null,
  group_position integer not null,
  visibility app.course_visibility not null default 'draft'::app.course_visibility,
  content_ready boolean not null default false,
  price_amount_cents integer,
  stripe_product_id text,
  active_stripe_price_id text,
  sellable boolean not null default false,
  drip_enabled boolean not null default false,
  drip_interval_days integer,
  cover_media_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint courses_pkey primary key (id),
  constraint courses_teacher_id_fkey
    foreign key (teacher_id) references app.auth_subjects (user_id),
  constraint courses_cover_media_id_fkey
    foreign key (cover_media_id) references app.media_assets (id),
  constraint courses_slug_key unique (slug),
  constraint courses_group_position_key unique (course_group_id, group_position),
  constraint courses_group_position_check check (group_position >= 0),
  constraint courses_title_not_blank_check check (btrim(title) <> ''),
  constraint courses_slug_not_blank_check check (btrim(slug) <> ''),
  constraint courses_price_amount_positive_check
    check (price_amount_cents is null or price_amount_cents > 0),
  constraint courses_public_requires_ready_check
    check (
      visibility <> 'public'::app.course_visibility
      or content_ready = true
    ),
  constraint courses_sellable_requires_public_ready_commerce_check
    check (
      sellable = false
      or (
        visibility = 'public'::app.course_visibility
        and content_ready = true
        and price_amount_cents is not null
        and stripe_product_id is not null
        and btrim(stripe_product_id) <> ''
        and active_stripe_price_id is not null
        and btrim(active_stripe_price_id) <> ''
      )
    ),
  constraint courses_drip_interval_check
    check (
      (
        drip_enabled = true
        and drip_interval_days is not null
        and drip_interval_days > 0
      )
      or (
        drip_enabled = false
        and drip_interval_days is null
      )
    )
);

create index courses_teacher_id_idx
  on app.courses (teacher_id);

create index courses_visibility_idx
  on app.courses (visibility);

create index courses_group_idx
  on app.courses (course_group_id, group_position);

create index courses_sellable_idx
  on app.courses (sellable)
  where sellable = true;

create unique index courses_stripe_product_id_key
  on app.courses (stripe_product_id)
  where stripe_product_id is not null;

create unique index courses_active_stripe_price_id_key
  on app.courses (active_stripe_price_id)
  where active_stripe_price_id is not null;

comment on table app.courses is
  'Canonical course authority: ownership, visibility, progression, readiness, and commerce.';

comment on column app.courses.teacher_id is
  'Single canonical course owner.';

comment on column app.courses.course_group_id is
  'Logical grouping of courses into a progression series.';

comment on column app.courses.group_position is
  'Explicit progression position within a course group. No implicit step semantics.';

comment on column app.courses.visibility is
  'Canonical course visibility. Published means visibility = public.';

comment on column app.courses.content_ready is
  'Backend-controlled readiness gate for public visibility and playback.';

comment on column app.courses.sellable is
  'Backend-controlled commerce flag. Not visibility authority.';

create or replace function app.enforce_course_cover_media_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_purpose app.media_purpose;
  v_media_type app.media_type;
begin
  if new.cover_media_id is null then
    return new;
  end if;

  select purpose, media_type
    into v_purpose, v_media_type
  from app.media_assets
  where id = new.cover_media_id;

  if not found then
    raise exception 'course cover media asset % does not exist', new.cover_media_id;
  end if;

  if v_purpose <> 'course_cover'::app.media_purpose then
    raise exception 'course cover media must have purpose course_cover';
  end if;

  if v_media_type <> 'image'::app.media_type then
    raise exception 'course cover media must be image';
  end if;

  return new;
end;
$$;

create trigger courses_cover_media_contract
before insert or update of cover_media_id
on app.courses
for each row
execute function app.enforce_course_cover_media_contract();

create table app.course_public_content (
  course_id uuid not null,
  short_description text not null,
  constraint course_public_content_pkey primary key (course_id),
  constraint course_public_content_course_id_fkey
    foreign key (course_id) references app.courses (id) on delete cascade,
  constraint course_public_content_short_description_not_blank_check
    check (btrim(short_description) <> '')
);

comment on table app.course_public_content is
  'Sibling public content surface. Does not control course visibility.';
