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

create or replace function app.canonical_redeem_referral_code(
  p_code text,
  p_email text,
  p_redeeming_user_id uuid,
  p_membership_id uuid,
  p_redeemed_at timestamptz default clock_timestamp()
)
returns app.memberships
language plpgsql
security definer
set search_path = pg_catalog, app
as $$
declare
  v_code text;
  v_email text;
  v_subject_email text;
  v_referral app.referral_codes%rowtype;
  v_membership app.memberships%rowtype;
  v_has_membership boolean := false;
  v_idempotent_redemption boolean := false;
  v_effective_at timestamptz;
  v_expires_at timestamptz;
begin
  if p_code is null or btrim(p_code) = '' then
    raise exception 'referral redemption requires code';
  end if;

  if p_email is null or btrim(p_email) = '' then
    raise exception 'referral redemption requires email';
  end if;

  if p_redeeming_user_id is null then
    raise exception 'referral redemption requires redeeming user id';
  end if;

  if p_membership_id is null then
    raise exception 'referral redemption requires explicit membership id';
  end if;

  if p_redeemed_at is null then
    raise exception 'referral redemption requires redeemed_at';
  end if;

  v_code := upper(btrim(p_code));
  v_email := lower(btrim(p_email));

  select email
    into v_subject_email
  from app.auth_subjects
  where user_id = p_redeeming_user_id;

  if not found then
    raise exception 'redeeming auth subject % does not exist', p_redeeming_user_id;
  end if;

  if v_subject_email is not null
     and lower(btrim(v_subject_email)) <> v_email then
    raise exception 'redeeming auth subject email does not match referral email';
  end if;

  select *
    into v_referral
  from app.referral_codes
  where code = v_code
    and email = v_email
  for update;

  if not found then
    raise exception 'referral code does not exist for the supplied email';
  end if;

  if v_referral.redeemed_by_user_id is not null then
    if v_referral.redeemed_by_user_id <> p_redeeming_user_id then
      raise exception 'referral code has already been redeemed by another user';
    end if;

    if v_referral.redeemed_at is null then
      raise exception 'referral code redemption state is invalid';
    end if;

    v_idempotent_redemption := true;
  end if;

  select *
    into v_membership
  from app.memberships
  where user_id = p_redeeming_user_id
  for update;

  v_has_membership := found;

  if v_has_membership then
    if v_membership.source <> 'referral'::app.membership_source then
      raise exception 'existing membership is not referral-sourced';
    end if;

    if not v_idempotent_redemption then
      raise exception 'redeeming user already has a referral membership';
    end if;
  end if;

  if v_idempotent_redemption then
    v_effective_at := v_referral.redeemed_at;
  else
    if v_referral.active = false then
      raise exception 'referral code is not active';
    end if;

    v_effective_at := p_redeemed_at;

    update app.referral_codes
       set active = false,
           redeemed_by_user_id = p_redeeming_user_id,
           redeemed_at = v_effective_at,
           updated_at = v_effective_at
     where id = v_referral.id
    returning * into v_referral;
  end if;

  if v_referral.free_days is not null then
    v_expires_at := v_effective_at + make_interval(days => v_referral.free_days);
  elsif v_referral.free_months is not null then
    v_expires_at := v_effective_at + make_interval(months => v_referral.free_months);
  else
    raise exception 'referral code has no grant duration';
  end if;

  if v_expires_at <= v_effective_at then
    raise exception 'referral grant expiry must be after effective time';
  end if;

  if v_has_membership then
    return v_membership;
  end if;

  insert into app.memberships (
    membership_id,
    user_id,
    status,
    source,
    effective_at,
    expires_at,
    canceled_at,
    ended_at,
    provider_customer_id,
    provider_subscription_id,
    created_at,
    updated_at
  )
  values (
    p_membership_id,
    p_redeeming_user_id,
    'active'::app.membership_status,
    'referral'::app.membership_source,
    v_effective_at,
    v_expires_at,
    null,
    null,
    null,
    null,
    v_effective_at,
    v_effective_at
  )
  returning * into v_membership;

  return v_membership;
end;
$$;

revoke all on function app.canonical_redeem_referral_code(
  text,
  text,
  uuid,
  uuid,
  timestamptz
) from public;

comment on function app.canonical_redeem_referral_code(
  text,
  text,
  uuid,
  uuid,
  timestamptz
) is
  'Canonical referral redemption function. It validates code, email, and redemption state, grants referral-sourced membership, and never creates orders, payments, course enrollments, auth, or onboarding authority.';
