-- CSV: schema, function, argtypes, returns, volatility, security, leakproof, lang
select
  n.nspname as schema,
  p.proname as function,
  pg_get_function_arguments(p.oid) as argtypes,
  pg_get_function_result(p.oid) as returns,
  case p.provolatile when 'i' then 'IMMUTABLE' when 's' then 'STABLE' else 'VOLATILE' end as volatility,
  case when p.prosecdef then 'SECURITY DEFINER' else 'SECURITY INVOKER' end as security,
  case when p.proleakproof then 'LEAKPROOF' else '' end as leakproof,
  l.lanname as lang
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_language l on l.oid = p.prolang
where n.nspname not in ('pg_catalog','information_schema')
order by n.nspname, p.proname;
