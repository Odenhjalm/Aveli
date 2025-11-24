# **🔥 Codex MEGA-PROMPT — LiveKit, Supabase, Backend, Full Pipeline Repair & Hardening**

**Uppdrag:**
Analysera och åtgärda alla problem i LiveKit-pipeline, webhook-kö, migrationsstruktur, RLS/policies, tabeller och backendintegration. Se till att backend bootar utan fel och att Supabase-schemat matchar backendens förväntningar till 100%.

**Du har full tillgång till:**

- hela projektets repo
- alla Supabase-scheman via MCP
- alla migrations
- alla backendfiler
- environment loaders
- loggar och tidigare körningar

**Du ska agera som fullstack dev (backend + DB + infra) med komplett autonomi inom projektet.**

---

# ✔️ **1. Skanna backendens LiveKit-pipeline**

Gör en full scanning av:

- `app/services/livekit_events.py`
- `app/repositories/livekit_jobs.py`
- event-handlers, poller, worker, scheduler
- all SQL som backend försöker köra

Identifiera allt backend förväntar sig att Supabase ska ha, t.ex.:

- tabeller
- triggers
- policies
- index
- funktioner
- sekvenser
- vyer

Notera ALLA strukturer backend använder.

---

# ✔️ **2. Skanna Supabase-instansen via MCP**

- Lista allt under schema `app`
- Lista migrations i `supabase/migrations/`
- Jämför databasens tabeller med backendens krav
- Identifiera saknade tabeller (t.ex. `app.livekit_webhook_jobs`)
- Identifiera saknade policies
- Identifiera saknade constraints
- Identifiera inkompletta eller gamla migrations

Du får automatiskt använda `supabase-mcp` för alla SQL-kommandon du behöver (SELECT, DESCRIBE, EXPLAIN etc.).

---

# ✔️ **3. Om tabellen inte finns – skapa rätt migration**

Om migrations saknas eller är fel:

1. Skapa en ny migrationsfil under `supabase/migrations/`
2. Följ projektets namngivningsstandard
3. Innehåll ska inkludera:

```
create table app.livekit_webhook_jobs (
    id bigint generated always as identity primary key,
    created_at timestamptz not null default now(),
    due_at timestamptz not null default now(),
    status text not null default 'pending',
    event_type text not null,
    payload jsonb not null,
    attempts int not null default 0,
    max_attempts int not null default 5,
    locked_at timestamptz,
    locked_by uuid,
    error_last text,
    error_history text[]
);

create index livekit_webhook_jobs_due_idx
    on app.livekit_webhook_jobs (due_at)
    where status = 'pending';

create index livekit_webhook_jobs_locked_idx
    on app.livekit_webhook_jobs (locked_at);

alter table app.livekit_webhook_jobs enable row level security;

create policy "backend can manage livekit jobs"
    on app.livekit_webhook_jobs
    for all
    using (true)
    with check (true);
```

4. Om backend kräver fler fält, lägg till dem.
5. Om backend kräver triggers (audit_touch / updated_at), lägg till dem.
6. Om backend kräver app-funktioner, lägg till dem.

---

# ✔️ **4. Utför migrationen**

När migrationen är klar:

- kör `supabase db push`
- verifiera att databasen nu innehåller tabellen
- kontrollera index, RLS, constraints, triggers etc.

---

# ✔️ **5. Verifiera backendflödet**

Starta backend genom repo-kommandot:

```
poetry run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Kontrollera loggarna:

- “LiveKit webhook worker started”
- INGA `UndefinedTable`
- INGA SQL-fel
- pollern ska loopa utan att kasta errors

Om backend fortfarande kastar något:

- Tolka felet
- Sök upp tabeller, policies eller strukturer
- Uppdatera migrationer tills allt fungerar perfekt

---

# ✔️ **6. Reparera även andra LiveKit-relaterade delar**

T.ex.:

- webhook-endpointen
- `app.livekit_rooms`
- `app.livekit_recordings`
- `app.livekit_participants`
- RLS-policies för lärare som ska hantera sessions
- internal API-nycklar som backend väntar på
- event queue + cleanup jobs
- triggers och TTL om backend använder sådana

Codex ska reparera ALLT som backend förväntar sig.

---

# ✔️ **7. Hårdgör pipeline och skapa stabilitet**

- Lägg till rimliga index
- Lägg till safety-checks på payloads
- Säkerställ att tabellen är redo för hög last
- Kontrollera att inget i backend kör "SELECT \*" med fel schema
- Kontrollera search_path i migrations
- Säkerställ att LiveKit-händelser sparas korrekt och låses atomiskt

---

# ✔️ **8. Leverera slutrapport**

När allt är klart ska du ge:

1. Bekräftelse att allt fungerar
2. Lista över tabeller/policies du skapat eller modifierat
3. Om du gjorde patchar i backend – redovisa vilka och varför
4. Bekräfta att backend nu startar rent
5. Bekräfta att LiveKit webhook polling fungerar
6. Bekräfta att databasens schema är helt synkat mot backendens kod

---

# ✔️ **Regler**

- Rör inte orelaterade system
- Ändra inte kod som inte behövs
- Följ repo-standard strikt
- Undvik duplicerade migrations
- Uppdatera endast där backend **tydligt kräver** det
- Allt ska vara 100% körbart direkt

---

# **🔥 MÅL:**

Backend startar **rent**, LiveKit-pipeline fungerar **felfritt**, Supabase-schema är **perfekt synkat**, inga fel i loggar, och hela backend är redo för produktion.
