-- CSV: grantee, schema, table, privilege_type, is_grantable
select
    grantee,
    table_schema,
    table_name,
    privilege_type,
    is_grantable
from information_schema.table_privileges
where table_schema not in ('pg_catalog','information_schema')
order by table_schema, table_name, grantee, privilege_type;
