\pset format aligned
\pset pager off

-- Överskrift
select '# Databasöversikt';

select '';
select 'Databas: ' || current_database();
select 'Serverversion: ' || version();
select '';

-- Extensions
select '## Extensions';
select string_agg(extname, ', ' order by extname) as "Aktiva extensions"
from pg_extension;

select '';

-- Scheman
select '## Scheman';
select string_agg(nspname, ', ' order by nspname) as "Scheman"
from pg_namespace
where nspname not like 'pg_%' and nspname <> 'information_schema';

select '';

-- Enum-typer
select '## Enum-typer';
select
  n.nspname as schema,
  t.typname as enum_type,
  string_agg(e.enumlabel, ', ' order by e.enumsortorder) as labels
from pg_type t
join pg_enum e on t.oid = e.enumtypid
join pg_namespace n on n.oid = t.typnamespace
group by n.nspname, t.typname
order by n.nspname, t.typname;

select '';

-- Tabeller & kolumner (sammandrag)
select '## Tabeller & kolumner (sammandrag)';

select
  table_schema,
  table_name,
  string_agg(
    column_name || ' ' || data_type || coalesce('('||character_maximum_length||')','')
    || case when is_nullable='NO' then ' NOT NULL' else '' end
    || coalesce(' DEFAULT '||column_default,'')
  , E'\n' order by ordinal_position) as columns
from information_schema.columns
where table_schema not in ('pg_catalog','information_schema')
group by table_schema, table_name
order by table_schema, table_name;

select '';

-- Primärnycklar
select '## Primärnycklar';
select
  n.nspname as schema,
  c.relname as table,
  pg_get_constraintdef(con.oid) as pk_def
from pg_constraint con
join pg_class c on c.oid = con.conrelid
join pg_namespace n on n.oid = c.relnamespace
where con.contype = 'p'
order by n.nspname, c.relname;

select '';

-- Utländska nycklar
select '## Utländska nycklar';
select
  n.nspname as schema,
  c.relname as table,
  con.conname as fk_name,
  pg_get_constraintdef(con.oid) as fk_def
from pg_constraint con
join pg_class c on c.oid = con.conrelid
join pg_namespace n on n.oid = c.relnamespace
where con.contype = 'f'
order by n.nspname, c.relname;

select '';

-- Index
select '## Index';
select
  schemaname as schema,
  tablename as table,
  indexname as index,
  indexdef
from pg_indexes
where schemaname not in ('pg_catalog','information_schema')
order by schemaname, tablename, indexname;

select '';

-- Triggers
select '## Triggers';
select
  event_object_schema as schema,
  event_object_table as table,
  trigger_name,
  action_timing || ' ' || event_manipulation as timing_event,
  action_statement
from information_schema.triggers
order by event_object_schema, event_object_table, trigger_name;

select '';

-- RLS på tabellnivå (flagga)
select '## Tabeller med RLS aktiverat';
select n.nspname as schema, c.relname as table, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relkind = 'r'
  and n.nspname not in ('pg_catalog','information_schema')
order by n.nspname, c.relname;
