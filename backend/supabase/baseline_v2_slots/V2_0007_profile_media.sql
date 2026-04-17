create table app.profile_media_placements (
  id uuid not null default gen_random_uuid(),
  subject_user_id uuid not null,
  media_asset_id uuid not null,
  visibility app.profile_media_visibility not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profile_media_placements_pkey primary key (id),
  constraint profile_media_placements_subject_user_id_fkey
    foreign key (subject_user_id) references app.auth_subjects (user_id) on delete cascade,
  constraint profile_media_placements_media_asset_id_fkey
    foreign key (media_asset_id) references app.media_assets (id),
  constraint profile_media_placements_subject_media_key
    unique (subject_user_id, media_asset_id)
);

create index profile_media_placements_subject_user_id_idx
  on app.profile_media_placements (subject_user_id);

create index profile_media_placements_published_idx
  on app.profile_media_placements (subject_user_id, visibility)
  where visibility = 'published'::app.profile_media_visibility;

comment on table app.profile_media_placements is
  'Canonical profile/community media placement source. Ownership is derived from subject_user_id.';

comment on column app.profile_media_placements.subject_user_id is
  'Canonical subject binding for profile/community media.';

comment on column app.profile_media_placements.visibility is
  'Profile media visibility. draft is hidden, published is visible in projections.';

create or replace function app.enforce_profile_media_asset_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_purpose app.media_purpose;
begin
  select purpose into v_purpose
  from app.media_assets
  where id = new.media_asset_id;

  if not found then
    raise exception 'profile media asset % does not exist', new.media_asset_id;
  end if;

  if v_purpose <> 'profile_media'::app.media_purpose then
    raise exception 'profile media must have purpose profile_media';
  end if;

  return new;
end;
$$;

create trigger profile_media_asset_contract
before insert or update of media_asset_id
on app.profile_media_placements
for each row
execute function app.enforce_profile_media_asset_contract();
