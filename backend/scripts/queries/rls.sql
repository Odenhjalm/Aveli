-- CSV: schema,table,policy_name,cmd,roles,permissive,using,with_check
select
    schemaname,
    tablename,
    policyname,
    cmd,
    roles,
    permissive,
    coalesce(qual, '') as using_expr,
    coalesce(with_check, '') as with_check_expr
from pg_policies
order by schemaname, tablename, policyname, cmd;
