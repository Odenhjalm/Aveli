# QA – Teacher Login & Gratis Introduktionskurser

## Förutsättningar
- Miljövariabler i `.env` bör innehålla `SUPABASE_URL` och `SUPABASE_ANON_KEY`.
- Testkonto: `teacher.local@example.com` / `ChangeMe123!`.

## Status (2024-11-23)
Jag kan inte verifiera mot Supabase från den här miljön (ingen nätverksåtkomst / saknade credentials). Stegen nedan är dokumenterade för manuell körning på en maskin med åtkomst:

1. **Verifiera miljövariabler**
   ```bash
   cat .env
   ```
   Kontrollera att URL och anon-key är satta.

2. **Starta appen**
   ```bash
   flutter run -d chrome
   ```

3. **Logga in som lärare**
   - E-post: `teacher.local@example.com`
   - Lösenord: `ChangeMe123!`
   - Bekräfta att `[AUTH] SignedIn` skrivs i loggen.

4. **Skapa kurser i Teacher Editor**
   - Navigera till `/teacher/editor`.
   - Skapa minst fem kurser med `Gratis introduktion` aktiverat.
   - Ladda upp omslagsbild (sparas i `storage.media`).

5. **Kontrollera i Supabase**
   ```sql
   select id, title, is_free_intro, cover_url
   from app.courses
   where created_by = '<user-id>' and is_free_intro = true;
   ```

6. **QA på landing**
   - Logga ut.
   - Öppna landing page; bekräfta att kursernas omslag syns och att "Gratis intro"-badge visas.
   - Klick på kurserna → `/course-intro` laddas.

7. **Dokumentera**
   - Ta screenshots (login, editor, landing).
   - Lägg till kort summering i `codex_update.md`.

## Rekommendation
Kör denna checklista i den miljö där Supabase-projektet är live. Uppdatera denna fil med datum/resultat efter genomförd QA.
