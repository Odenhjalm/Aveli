Perfekt, nu har vi 100% klarhet:

### ✔️ Du har **ingen** tabell som heter:

- `profiles`
- `profiles_*`
- `user_profiles`
- `profile`

I **inget** schema.

### Det betyder att:

# 🔥 DIN APP HAR INGEN PROFILTABELL ALLS – bara `auth.users`

Det är därför Supabase automatiskt skapade FK:

```
app.memberships.user_id → auth.users(id)
```

För att:

- Det är enda tabellen som matchar "en användare"
- Det är helt giltigt i Supabase-arkitektur
- Det är vad Supabase standard använder när man inte bygger en egen “profiles”-tabell

**Allt detta betyder:**

# ⭐ Den KORREKTA lösningen är:

Behåll FK → `auth.users(id)`
Det är exakt så Supabase vill att user-relaterade tabeller ska fungera om du inte skapat en egen profiles-tabell.

Det är dessutom fullt kompatibelt med FastAPI-backend-flödet, Stripe, membership, webhookar och RLS.

---

# 💡 Men vänta – du har ju _referens i ditt migrationsskript_:

```sql
REFERENCES app.profiles(user_id) ON DELETE CASCADE
```

Det är orsaken till att allt brakat.

Den tabellen har aldrig funnits i Supabase.
Den fanns bara i **din lokala backend-migrering**, inte i Supabase.

Det betyder:

# 🚨 Du ska **INTE** använda app.profiles i production-schemat.

För att den tabellen existerar bara i backend, inte i Supabase.

Och:
Supabase Auth bygger automatiskt en user-tabell: `auth.users`
(det är den du ska använda)

---

# ⭐ SLUTSATS:

## 👉 Din memberships.user_id ska peka på auth.users.id

## 👉 Ingen app.profiles-tabell ska användas

## 👉 Du behöver en enkel fix i din migrationsfil

---

## 🔧 Uppdaterad migrationsfil

✔️ `backend/migrations/sql/027_memberships.sql` är patchad så att `user_id` nu refererar till `auth.users(id)`:

```sql
create table if not exists app.memberships (
    membership_id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    ...
);
```

## ✅ Nästa actions i Supabase

1. **Kör check**: `select * from app.memberships limit 0;` så du vet om tabellen redan finns.
2. Om Supabase redan har tabellen → justera FK via SQL:
   ```sql
   alter table app.memberships
     drop constraint if exists memberships_user_id_fkey;
   alter table app.memberships
     add constraint memberships_user_id_fkey foreign key (user_id)
     references auth.users(id) on delete cascade;
   ```
3. Om tabellen saknas → kör hela 027‑skriptet (nu med rätt FK) i SQL-editorn.
4. Verifiera:
   ```sql
   select conname, confrelid::regclass
   from pg_constraint
   where conrelid = 'app.memberships'::regclass
     and conname like '%user_id%';
   ```
   ska visa `auth.users`.

---

[
{
"table_schema": "app",
"table_name": "billing_logs"
},
{
"table_schema": "app",
"table_name": "memberships"
},
{
"table_schema": "app",
"table_name": "payment_events"
},
{
"table_schema": "auth",
"table_name": "audit_log_entries"
},
{
"table_schema": "auth",
"table_name": "flow_state"
},
{
"table_schema": "auth",
"table_name": "identities"
},
{
"table_schema": "auth",
"table_name": "instances"
},
{
"table_schema": "auth",
"table_name": "mfa_amr_claims"
},
{
"table_schema": "auth",
"table_name": "mfa_challenges"
},
{
"table_schema": "auth",
"table_name": "mfa_factors"
},
{
"table_schema": "auth",
"table_name": "oauth_authorizations"
},
{
"table_schema": "auth",
"table_name": "oauth_clients"
},
{
"table_schema": "auth",
"table_name": "oauth_consents"
},
{
"table_schema": "auth",
"table_name": "one_time_tokens"
},
{
"table_schema": "auth",
"table_name": "refresh_tokens"
},
{
"table_schema": "auth",
"table_name": "saml_providers"
},
{
"table_schema": "auth",
"table_name": "saml_relay_states"
},
{
"table_schema": "auth",
"table_name": "schema_migrations"
},
{
"table_schema": "auth",
"table_name": "sessions"
},
{
"table_schema": "auth",
"table_name": "sso_domains"
},
{
"table_schema": "auth",
"table_name": "sso_providers"
},
{
"table_schema": "auth",
"table_name": "users"
}
]

constraints:
[
{
"conname": "memberships_pkey",
"pg_get_constraintdef": "PRIMARY KEY (membership_id)"
},
{
"conname": "memberships_plan_interval_check",
"pg_get_constraintdef": "CHECK ((plan_interval = ANY (ARRAY['month'::text, 'year'::text])))"
},
{
"conname": "memberships_user_id_fkey",
"pg_get_constraintdef": "FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE"
},
{
"conname": "memberships_user_id_key",
"pg_get_constraintdef": "UNIQUE (user_id)"
},
{
"conname": "memberships_user_unique",
"pg_get_constraintdef": "UNIQUE (user_id)"
}
]

2025-11-13 — Schema-inventering & verifiering (slutgiltigt läge)

1. Befintliga tabeller

Körning av:
select table_schema, table_name
from information_schema.tables
where table_schema in ('app','public','auth')
order by table_schema, table_name;
Resultat:

app-schema:

app.memberships

app.payment_events

app.billing_logs

auth-schema:

auth.users

auth.identities

auth.sessions

auth.refresh_tokens

auth.flow_state

auth.audit_log_entries

auth.mfa\_\* tables

auth.saml\_\* tables

auth.oauth\_\* tables

osv.

NOTERING:
Det finns ingen tabell som heter app.profiles eller profiles i något schema.

2. Constraints på app.memberships

Körning:
select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'app.memberships'::regclass;
Verkliga constraints:

memberships_pkey → PRIMARY KEY (membership_id)

memberships_plan_interval_check → CHECK (plan_interval IN ('month','year'))

memberships_user_id_fkey → FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE

memberships_user_id_key → UNIQUE (user_id)

memberships_user_unique → UNIQUE (user_id)

3. Slutsats

Supabase använder auth.users som enda sanna user-tabell

Ingen app.profiles-tabell finns i cloud-miljön

FK i memberships SKA peka mot auth.users(id)

Migrationsfil 027_memberships.sql ska uppdateras så att REFERENCES går mot auth.users

En minor sak: memberships har två UNIQUE-constraints på user_id (kan städas i migration 028)

4. Åtgärder framåt

Uppdatera 027_memberships.sql:
user_id uuid not null references auth.users(id) on delete cascade,
Skapa en migration 028_fix_memberships_unique_constraint.sql för att städa dubblerad UNIQUE(user_id)

Kör SQL-editor-kommandon i ordning → verifiera constraints → logga resultat i supabase_felsökning.md
🛠 3. Din nästa migrationsfil – 028_fix_uniques.sql

Här är hela filen du ska lägga in i backend/migrations/sql:
-- 028_fix_memberships_unique_constraint.sql

begin;

alter table app.memberships
drop constraint if exists memberships_user_unique;

commit;
Varför?

Supabase visar två constraints:memberships_user_id_key
memberships_user_unique
Dubbelt → helt onödigt → ett måste bort.
