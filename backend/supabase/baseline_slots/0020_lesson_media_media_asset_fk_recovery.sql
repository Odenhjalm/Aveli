alter table app.lesson_media
  add constraint lesson_media_media_asset_id_fkey
  foreign key (media_asset_id) references app.media_assets (id);
