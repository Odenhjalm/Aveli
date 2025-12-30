-- 023_postgrest_grants.sql
-- Grant schema/table/function access for PostgREST roles (RLS still enforced).

begin;

grant usage on schema app to anon, authenticated, service_role;

grant select, insert, update, delete on all tables in schema app to anon, authenticated, service_role;
grant usage, select on all sequences in schema app to anon, authenticated, service_role;
grant execute on all functions in schema app to anon, authenticated, service_role;

commit;
