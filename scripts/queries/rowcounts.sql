-- CSV: schema, table, est_rows
select
    n.nspname as schema,
    c.relname
as table,
  c.reltuples::bigint as est_rows
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relkind = 'r'
  and n.nspname not in
('pg_catalog','information_schema')
order by est_rows desc, n.nspname, c.relname;
