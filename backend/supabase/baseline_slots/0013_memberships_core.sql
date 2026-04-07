create table app.memberships (
  membership_id uuid not null,
  user_id uuid not null,
  status text not null,
  end_date timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  constraint memberships_pkey primary key (membership_id),
  constraint memberships_user_id_key unique (user_id)
);
