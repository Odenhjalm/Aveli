-- 20260204120000_home_player_upload_wav_pipeline.sql
-- Allow Home player uploads to reference media_assets (WAV -> MP3 pipeline).

begin;

alter table app.home_player_uploads
  add column if not exists media_asset_id uuid references app.media_assets(id);

alter table app.home_player_uploads
  alter column media_id drop not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'home_player_uploads_media_ref_check'
      and conrelid = 'app.home_player_uploads'::regclass
  ) then
    alter table app.home_player_uploads
      add constraint home_player_uploads_media_ref_check
      check ((media_id is null) <> (media_asset_id is null));
  end if;
end
$$;

create index if not exists idx_home_player_uploads_media_asset
  on app.home_player_uploads(media_asset_id);

commit;

