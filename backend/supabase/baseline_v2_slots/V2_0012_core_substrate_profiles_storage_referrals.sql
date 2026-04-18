create table app.profiles (
  user_id uuid not null,
  display_name text,
  bio text,
  avatar_media_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint profiles_pkey primary key (user_id),

  constraint profiles_user_id_fkey
    foreign key (user_id)
    references app.auth_subjects (user_id)
    on delete cascade,

  constraint profiles_avatar_media_id_fkey
    foreign key (avatar_media_id)
    references app.media_assets (id),

  constraint profiles_display_name_not_blank_check
    check (display_name is null or btrim(display_name) <> '')
);

create index profiles_avatar_media_id_idx
  on app.profiles (avatar_media_id)
  where avatar_media_id is not null;

comment on table app.profiles is
  'Projection-only profile persistence. It must not own onboarding, role, membership, billing, or media authority.';

comment on column app.profiles.display_name is
  'Editable profile projection text only.';

comment on column app.profiles.avatar_media_id is
  'Projection of the selected avatar media asset. Authored media placement truth remains app.profile_media_placements.';

create or replace function app.enforce_profile_avatar_projection_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_exists boolean;
begin
  if new.avatar_media_id is null then
    return new;
  end if;

  select exists (
    select 1
    from app.profile_media_placements as pmp
    join app.media_assets as ma
      on ma.id = pmp.media_asset_id
    where pmp.subject_user_id = new.user_id
      and pmp.media_asset_id = new.avatar_media_id
      and pmp.visibility = 'published'::app.profile_media_visibility
      and ma.purpose = 'profile_media'::app.media_purpose
      and ma.media_type = 'image'::app.media_type
  )
  into v_exists;

  if not v_exists then
    raise exception 'profile avatar projection must reference published profile image placement';
  end if;

  return new;
end;
$$;

create trigger profiles_avatar_projection_contract
before insert or update of avatar_media_id
on app.profiles
for each row
execute function app.enforce_profile_avatar_projection_contract();

create schema if not exists storage;

create table storage.buckets (
  id text not null,
  name text not null,
  public boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint buckets_pkey primary key (id),

  constraint buckets_name_key unique (name),

  constraint buckets_id_not_blank_check
    check (btrim(id) <> ''),

  constraint buckets_name_not_blank_check
    check (btrim(name) <> '')
);

comment on table storage.buckets is
  'Physical storage bucket substrate only. Storage objects and buckets do not own Aveli domain authority.';

create table storage.objects (
  id uuid not null default gen_random_uuid(),
  bucket_id text not null,
  name text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_accessed_at timestamptz,

  constraint objects_pkey primary key (id),

  constraint objects_bucket_id_fkey
    foreign key (bucket_id)
    references storage.buckets (id)
    on delete cascade,

  constraint objects_bucket_name_key unique (bucket_id, name),

  constraint objects_bucket_id_not_blank_check
    check (btrim(bucket_id) <> ''),

  constraint objects_name_not_blank_check
    check (btrim(name) <> '')
);

create index objects_bucket_id_idx
  on storage.objects (bucket_id);

comment on table storage.objects is
  'Physical storage object catalog only. Object presence can support verification but must not become media, ownership, access, or delivery authority.';

create table app.media_resolution_failures (
  id uuid not null default gen_random_uuid(),
  lesson_media_id uuid,
  mode text not null,
  reason text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint media_resolution_failures_pkey primary key (id),

  constraint media_resolution_failures_lesson_media_id_fkey
    foreign key (lesson_media_id)
    references app.lesson_media (id)
    on delete set null,

  constraint media_resolution_failures_mode_check
    check (
      mode in (
        'editor_insert',
        'editor_preview',
        'student_render'
      )
    ),

  constraint media_resolution_failures_reason_check
    check (
      reason in (
        'missing_object',
        'bucket_mismatch',
        'key_format_drift',
        'cannot_sign',
        'unsupported'
      )
    )
);

create index media_resolution_failures_lesson_media_id_idx
  on app.media_resolution_failures (lesson_media_id);

create index media_resolution_failures_created_at_idx
  on app.media_resolution_failures (created_at);

comment on table app.media_resolution_failures is
  'Media delivery observability support only. This table must not own media identity, placement, access, readiness, or delivery authority.';

create table app.referral_codes (
  id uuid not null default gen_random_uuid(),
  code text not null,
  teacher_id uuid not null,
  email text not null,
  free_days integer,
  free_months integer,
  active boolean not null default true,
  redeemed_by_user_id uuid,
  redeemed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint referral_codes_pkey primary key (id),

  constraint referral_codes_code_key unique (code),

  constraint referral_codes_teacher_id_fkey
    foreign key (teacher_id)
    references app.auth_subjects (user_id),

  constraint referral_codes_redeemed_by_user_id_fkey
    foreign key (redeemed_by_user_id)
    references app.auth_subjects (user_id),

  constraint referral_codes_code_format_check
    check (code = upper(btrim(code)) and btrim(code) <> ''),

  constraint referral_codes_email_format_check
    check (email = lower(btrim(email)) and btrim(email) <> ''),

  constraint referral_codes_duration_exactly_one_check
    check (
      (
        free_days is not null
        and free_days > 0
        and free_months is null
      )
      or
      (
        free_months is not null
        and free_months > 0
        and free_days is null
      )
    ),

  constraint referral_codes_redemption_pair_check
    check (
      (
        redeemed_by_user_id is null
        and redeemed_at is null
      )
      or
      (
        redeemed_by_user_id is not null
        and redeemed_at is not null
      )
    )
);

create index referral_codes_teacher_id_idx
  on app.referral_codes (teacher_id);

create index referral_codes_email_idx
  on app.referral_codes (email);

create index referral_codes_redeemable_idx
  on app.referral_codes (code, email)
  where active = true and redeemed_by_user_id is null;

comment on table app.referral_codes is
  'Canonical referral identity and lifecycle authority. Referral redemption may grant referral-sourced membership but must not create order or payment authority.';

comment on column app.referral_codes.teacher_id is
  'Teacher subject that issued the referral code.';

comment on column app.referral_codes.email is
  'Lowercase invited recipient email used to validate redemption eligibility.';
