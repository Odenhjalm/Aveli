alter table app.media_assets
  drop constraint if exists media_assets_state_check;

alter table app.media_assets
  add constraint media_assets_state_check
  check (state in ('pending_upload', 'uploaded', 'processing', 'ready', 'failed'));
