# Supabase Playbook

Steg-för-steg för att flytta MVP-schemat till Supabase och aktivera RLS.

1. **Exportera schema**
   ```bash
   pg_dump --schema=app --schema=auth --schema-only --no-owner --dbname="$DATABASE_URL" > supabase/app_schema.sql
   ```
2. **Kör i Supabase SQL Editor** – klistra in innehållet från `backend/migrations/sql/*.sql` i rätt ordning (001 → 026).
3. **Koppla `app.profiles.user_id` till Supabase auth** – sätt FK mot `auth.users`. (I Supabase UI: Table editor → app.profiles → Relationships.)
4. **Aktivera RLS** för varje tabell och ersätt våra kommentarer:
   ```sql
   alter table app.profiles enable row level security;
   create policy "Self access" on app.profiles
     for select using (auth.uid() = user_id);
   ```
   Upprepa för `app.service_orders`, `app.payments`, `app.seminar_attendees` etc.
5. **Policies för publicerade resurser** – skapa `policy allow_public_active_services` på `app.services` med `using (status = 'active')`.
6. **Supabase functions** – skapa `rpc`-helpers om vi behöver server-side inserts (t.ex. `rpc_insert_service_order`).
7. **Konfiguration i Flutter** – uppdatera `Supabase.instance.initialize(...)` samt `MvpApiClient` om du byter från lokal backend till edge functions.
8. **Verifiering** – kör `supabase db diff --linked` och dubbelkolla att `app.activities_feed` är en view (Supabase stödjer read-only). Testa flödet med `scripts/qa_teacher_smoke.py` mot Supabase REST/Edge innan skarp drift.
