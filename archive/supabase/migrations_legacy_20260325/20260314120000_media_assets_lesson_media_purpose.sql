-- Allow ready lesson image/document/video assets to persist in app.media_assets.

begin;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'app'
      and table_name = 'media_assets'
      and column_name = 'purpose'
  ) then
    alter table app.media_assets
      drop constraint if exists media_assets_purpose_check;

    alter table app.media_assets
      add constraint media_assets_purpose_check
      check (
        purpose in (
          'lesson_audio',
          'course_cover',
          'home_player_audio',
          'lesson_media'
        )
      );
  end if;
end
$$;

commit;
