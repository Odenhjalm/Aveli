-- Allow passthrough lesson assets to persist as video/document media_assets.

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
      and column_name = 'media_type'
  ) then
    return;
  end if;

  select pg_get_constraintdef(c.oid)
    into constraint_def
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where c.conname = 'media_assets_media_type_check'
    and n.nspname = 'app'
    and t.relname = 'media_assets'
    and c.contype = 'c'
  limit 1;

  if constraint_def is null then
    alter table app.media_assets
      add constraint media_assets_media_type_check
      check (media_type in ('audio', 'image', 'video', 'document'));
  elsif constraint_def not ilike '%video%' or constraint_def not ilike '%document%' then
    select array_agg(distinct m[1] order by m[1])
      into allowed_values
    from regexp_matches(constraint_def, '''([^'']+)''', 'g') as m;

    if allowed_values is null or array_length(allowed_values, 1) is null then
      allowed_values := array['audio', 'image'];
    end if;

    if not ('video' = any (allowed_values)) then
      allowed_values := array_append(allowed_values, 'video');
    end if;

    if not ('document' = any (allowed_values)) then
      allowed_values := array_append(allowed_values, 'document');
    end if;

    select string_agg(quote_literal(v), ', ' order by v)
      into values_list
    from unnest(allowed_values) as v;

    if values_list is null or values_list = '' then
      values_list := '''audio'', ''image'', ''video'', ''document''';
    end if;

    execute 'alter table app.media_assets drop constraint media_assets_media_type_check';
    execute 'alter table app.media_assets add constraint media_assets_media_type_check check (media_type in (' || values_list || '))';
  end if;
end
$$;

commit;
