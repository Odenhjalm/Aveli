# SECURITY DEFINER Audit — 2025-10-18

## Källa & metod

- Kör `python scripts/security_definer_audit.py` för att läsa alla `out/db_snapshot_*/*functions.csv` och lista funktioner markerade som `SECURITY DEFINER`.
- Granskade även versionshanterad SQL (`database/*.sql`, `backend/migrations/sql/*.sql`) via `rg -ni "security definer"`.

## Observationer

1. **0 SECURITY DEFINER-funktioner i snapshotterna** `db_snapshot_20251012_210745`, `db_snapshot_20251012_210948`, `db_snapshot_20251012_211114`, `db_snapshot_20251025_124937`. Alla `app.*`-funktioner (t.ex. `set_updated_at`, `is_seminar_host`) är `SECURITY INVOKER`.
2. Git-repot innehåller inga `SECURITY DEFINER`-deklarationer i schema- eller migrationsfiler.
3. Historiska dokument (`docs/archive/agent_iaktagelser.md`) refererar till funktioner som *bör* vara `SECURITY DEFINER` (`app.approve_teacher`, `app.reject_teacher`, `app.start_order`, `app.complete_order`, `app.claim_purchase`, `app.is_teacher`, `app.free_consumed_count`, `app.can_access_course`), men dessa finns inte i den versionerade SQL-koden eller snapshotterna.

## Slutsatser

- Utan att funktionerna finns versionerade går det inte att verifiera eller härda `SET search_path`, `auth.uid()`-guard eller avsaknad av dynamiska `EXECUTE`.
- Det är sannolikt att funktionerna endast lever i en extern Supabase-instans eller att logiken har flyttats till Python-backenden. I båda fallen saknas “single source of truth” i repo.

## Rekommenderade nästa steg

1. **Exportera verkliga funktioner** från primärdatabasen (Supabase/Postgres) och checka in dem under `backend/migrations/sql/` eller `database/*.sql`. Använd `scripts/dump_db_snapshot.sh` eller `pg_dump --schema=app --section=pre-data` för att få definitionerna.
2. **Standardisera mönster** när funktionerna återintroduceras:
   ```sql
   create or replace function app.complete_order(p_order_id uuid)
   returns void
   language plpgsql
   security definer
   set search_path = app, public
   as $$
   declare
     uid uuid := auth.uid();
   begin
     if uid is null then
       raise exception 'missing auth context';
     end if;
     -- validera ägarskap/roll här
     ...
   end;
   $$;
   ```
   - Börja varje funktion med `uid uuid := auth.uid();` (och ev. rollfetch) samt ägarskaps-/rollkontroll innan mutationer.
   - Undvik dynamisk SQL; nyttja parametrar och CTE:er i stället för `EXECUTE`.
3. **Inför lint i CI**: återanvänd `scripts/security_definer_audit.py` i GitHub Actions för att faila om nya snapshotter innehåller `SECURITY DEFINER`-funktioner utan explicit `SET search_path`.
4. **Dokumentera lägesrapport** i `tasks.md` (Backlog-punkt 1) när riktiga funktioner har checkats in, så nästa iteration kan fokusera på själva hårdningen.
