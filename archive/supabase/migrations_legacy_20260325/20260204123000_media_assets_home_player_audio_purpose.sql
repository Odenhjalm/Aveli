-- 20260204123000_media_assets_home_player_audio_purpose.sql
-- Allow WAV ingest pipeline to use purpose = 'home_player_audio'.

begin;

do $$
declare
  constraint_def text;
  allowed_values text[];
  values_list text;
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'app'
      and table_name = 'media_assets'
      and column_name = 'purpose'
  ) then
    -- Media pipeline not installed in this database; nothing to do.
    return;
  end if;

  select pg_get_constraintdef(c.oid)
    into constraint_def
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where c.conname = 'media_assets_purpose_check'
    and n.nspname = 'app'
    and t.relname = 'media_assets'
    and c.contype = 'c'
  limit 1;

  if constraint_def is null then
    alter table app.media_assets
      add constraint media_assets_purpose_check
      check (purpose in ('lesson_audio', 'course_cover', 'home_player_audio'));
  elsif constraint_def not ilike '%home_player_audio%' then
    select array_agg(distinct m[1] order by m[1])
      into allowed_values
    from regexp_matches(constraint_def, '''([^'']+)''', 'g') as m;

    if allowed_values is null or array_length(allowed_values, 1) is null then
      allowed_values := array['lesson_audio', 'course_cover'];
    end if;

    if not ('home_player_audio' = any (allowed_values)) then
      allowed_values := array_append(allowed_values, 'home_player_audio');
    end if;

    select string_agg(quote_literal(v), ', ' order by v)
      into values_list
    from unnest(allowed_values) as v;

    if values_list is null or values_list = '' then
      values_list := '''lesson_audio'', ''course_cover'', ''home_player_audio''';
    end if;

    execute 'alter table app.media_assets drop constraint media_assets_purpose_check';
    execute 'alter table app.media_assets add constraint media_assets_purpose_check check (purpose in (' || values_list || '))';
  end if;
end
$$;

commit;
