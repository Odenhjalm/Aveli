SELECT CASE WHEN to_regclass('storage.buckets') IS NULL THEN 'false' ELSE 'true' END AS storage_exists \gset
\if :storage_exists
  select
      b.id as bucket_id,
      b.public as is_public,
      b.file_size_limit,
      b.allowed_mime_types
  from storage.buckets b
  order by b.id;
\else
  -- return no rows if storage.buckets saknas
  select null::text as bucket_id, null::boolean as is_public,
         null::bigint as file_size_limit, null::text as allowed_mime_types
  where false;
\endif

-- Policys på storage.objects (med samma format som rls.sql)
select
    schemaname,
    tablename,
    policyname,
    cmd,
    roles,
    permissive,
    coalesce(qual,'') as using_expr,
    coalesce(with_check,'') as with_check_expr
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
order by policyname, cmd;
