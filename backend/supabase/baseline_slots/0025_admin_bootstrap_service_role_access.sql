BEGIN;

REVOKE EXECUTE ON FUNCTION app.bootstrap_first_admin(uuid)
FROM public, anon, authenticated;

GRANT EXECUTE ON FUNCTION app.bootstrap_first_admin(uuid)
TO service_role;

COMMIT;
