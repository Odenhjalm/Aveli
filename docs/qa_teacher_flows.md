# QA Röktest – Kursstudio & Mediaflöden

Det här dokumentet beskriver ett minimalt röktest för att säkerställa att lärarflödena fungerar mot den lokala FastAPI-backenden.

## Förutsättningar
- Lokalt backend-API körs (`uvicorn app.main:app --reload`).
- Postgres instans med seedade användare (kör `scripts/setup_local_backend.sh` vid behov).
- Flutter-appen konfigurerad att peka på `http://localhost:8000` via `.env` eller `--dart-define`.
- Testkonton:
  - Lärare: `teacher@example.com` / `teacher123`
  - Elev: `student@example.com` / `student123`

## 1. Lärarflöde – Kurseditor
1. **Logga in som lärare** i Flutter-appen.
2. Navigera till Kursstudio (`/studio`).
3. Skapa en ny kurs:
   - Titel, slug, beskrivning, pris (>0), markera ej publicerad.
   - Spara och verifiera att kursen syns i listan och att backend returnerar 200.
4. Skapa en modul (`POST /studio/modules`).
5. Skapa en lektion (`POST /studio/lessons`).
6. Sätt lektionen som introduktion (`PATCH /studio/lessons/{id}/intro`).

## 2. Mediauppladdning & Kö
1. Ladda upp minst tre filer (bild, video, ljud) via nya UI-knapparna.
2. Bekräfta att UI visar köade jobb med progress.
3. Kontrollera att backend svarar 200 och att filerna finns i `media/<course>/<lesson>/`.
4. Avbryt en pågående uppladdning; säkerställ att status ändras till *avbruten* och att filen saknas på disk.
5. Tryck "Försök igen" på en misslyckad/avbruten upload och verifiera att den raderar den gamla statusen och laddar upp.
6. Ladda ner en fil via UI och säkerställ att filen sparas lokalt utan korruption.

## 3. Kurs- & Studentvy
1. Publicera kursen (`PATCH /studio/courses/{id}` sätt `is_published = true`).
2. Logga in som elev och gå till kurslistan.
   - Verifiera att kursen visas i `/courses` och att introsektionen populeras.
3. Öppna kursdetaljen och kontrollera att modul-/lektionslistor matchar lärarens data.
4. Försök hämta media som elev – endast intro-filer ska vara åtkomliga (`bucket = public-media`).
5. Enrolla i kursen (free intro) och säkerställ att status uppdateras i backend (`app.enrollments`).

## 4. Quiz-flöde
1. Som lärare: tryck "Skapa/Hämta quiz" i studion.
2. Lägg till minst en fråga av varje typ.
3. Som elev: öppna kursens quiz-flik och säkerställ att frågorna visas.
4. Skicka in svar (`POST /courses/quiz/{id}/submit`) och kontrollera att resultatet beräknas.

## 5. Felhantering
- Försök ladda upp en fil >250 MB och verifiera att API returnerar 413 och att UI visar fel i kön.
- Ladda upp en fil med otillåtet MIME (t.ex. `.exe`) och kontrollera att backend ger 415 och att jobben markeras som misslyckade.
- Stäng av backend mitt under en uppladdning; jobben ska gå till *pending* och retrya automatiskt med backoff.

## 6. Städning
1. Radera media, lektioner, moduler och kurs. Säkerställ att filerna tas bort från `media/` och att UI/ponnylistor uppdateras utan krascher.
2. Kör `pytest tests/test_courses_studio.py` och `flutter test` för att säkerställa regressionsfri kod innan du avslutar rök-testet.

> Rekommendation: notera tidsstämplar, API-responskoder och eventuella konsolvarningar under testpasset. Använd loggarna för att uppdatera `flutter_dart_error.md` vid nya problem.
