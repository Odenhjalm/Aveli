create table app.profiles (
  user_id uuid not null,
  display_name text,
  avatar_media_id uuid,
  bio text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_pkey primary key (user_id)
);

comment on table app.profiles is
  'Projection-only profile surface derived from canonical auth + subject state. Non-authoritative.';
