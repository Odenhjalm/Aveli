do $$
declare
  external_fk record;
begin
  for external_fk in
    select distinct
      src_ns.nspname as source_schema,
      src.relname as source_table,
      con.conname as constraint_name
    from pg_constraint con
    join pg_class src on src.oid = con.conrelid
    join pg_namespace src_ns on src_ns.oid = src.relnamespace
    join pg_class tgt on tgt.oid = con.confrelid
    join pg_namespace tgt_ns on tgt_ns.oid = tgt.relnamespace
    where con.contype = 'f'
      and src_ns.nspname = 'app'
      and tgt_ns.nspname in ('auth', 'storage')
      and (
        (src.relname = 'profiles' and exists (
          select 1
          from unnest(con.conkey) as key(attnum)
          join pg_attribute att
            on att.attrelid = src.oid
           and att.attnum = key.attnum
          where att.attname = 'user_id'
        ))
        or
        (src.relname = 'memberships' and exists (
          select 1
          from unnest(con.conkey) as key(attnum)
          join pg_attribute att
            on att.attrelid = src.oid
           and att.attnum = key.attnum
          where att.attname = 'user_id'
        ))
      )
  loop
    execute format(
      'alter table %I.%I drop constraint if exists %I',
      external_fk.source_schema,
      external_fk.source_table,
      external_fk.constraint_name
    );
  end loop;
end
$$;

alter table if exists "app"."profiles"
  drop constraint if exists "profiles_user_id_fkey";

alter table if exists "app"."memberships"
  drop constraint if exists "memberships_user_id_fkey";

-- No extra indexes are added here:
-- - app.profiles.user_id is already primary-key indexed
-- - app.memberships.user_id is already uniquely indexed in slot 0017 when present
