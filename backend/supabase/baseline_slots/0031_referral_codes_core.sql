create table if not exists app.referral_codes (
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
  constraint referral_codes_pkey primary key (id),
  constraint referral_codes_code_key unique (code),
  constraint referral_codes_code_canonical_check check (
    code = upper(btrim(code))
    and btrim(code) <> ''
  ),
  constraint referral_codes_email_canonical_check check (
    email = lower(btrim(email))
    and btrim(email) <> ''
  ),
  constraint referral_codes_duration_check check (
    (
      free_days is not null
      and free_months is null
      and free_days > 0
    )
    or (
      free_days is null
      and free_months is not null
      and free_months > 0
    )
  ),
  constraint referral_codes_redemption_pair_check check (
    (
      redeemed_by_user_id is null
      and redeemed_at is null
    )
    or (
      redeemed_by_user_id is not null
      and redeemed_at is not null
    )
  ),
  constraint referral_codes_teacher_id_fkey
    foreign key (teacher_id) references app.auth_subjects (user_id),
  constraint referral_codes_redeemed_by_user_id_fkey
    foreign key (redeemed_by_user_id) references app.auth_subjects (user_id)
);

create index if not exists idx_referral_codes_email
  on app.referral_codes (lower(email));

create index if not exists idx_referral_codes_redeemable
  on app.referral_codes (code, lower(email))
  where active is true
    and redeemed_by_user_id is null;

comment on table app.referral_codes is
  'Canonical referral identity and lifecycle substrate only. Referral redemption remains post-auth and membership grants remain owned by app.memberships.';
