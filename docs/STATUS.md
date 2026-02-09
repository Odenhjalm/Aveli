Aveli – Statusöversikt

- DB-reset: Idempotenta reparationer och säkra DROP/ALTER i `scripts/reset_backend.sh` fixar bl.a. saknad `order_id`, `body`-kolumnfel, säkra view-drops (`service_reviews` m.fl.) samt skydd mot dubblett-index/constraints.
- Alembic: Ej i bruk. SQL-fallback i migrations och reset-skript (sekventiellt, säkra guards) är införda.
- Auth: Passlib/bcrypt-varning eliminerad – `bcrypt` är pinnad till `<4` i `backend/pyproject.toml` och uppdaterad i `poetry.lock`.
- Editor/Media: Robust MIME-detektion via `package:mime`; auto-insert för bild/video/ljud efter upload; inline-ljudspelare (Quill custom embed + builder) samt block-renderad lektionsvideo i editor/studentvy via samma `InlineVideoPlayer`-komponent som Home (responsiv layout + semantiketiketter). Klick/tap på videoytan växlar play/pause/resume i både Home och editor.
- Android bilder: Förbättrad robusthet. `AppAvatar` (cirkulär nätbild med fallback), `CourseCard` och `ServiceCard` använder `errorBuilder` + tydlig placeholder. `CoursesGrid` hade redan gradient-fallback. Nästa steg: inventera ev. cleartext/HTTPS och auth-skyddade bild-URL:er. HTTPS-policy sammanfattad nedan.
- Import av kursinnehåll: `scripts/import_course.py` + manifest (YAML/JSON). Stöd för `cover_path` och flaggan `--create-assets-lesson` som lägger omslag i separat modul/lektion (`_Assets`/`_Course Assets`). Studentvyn döljer moduler/lektioner vars titel börjar med `_`.
- Filväljare (web): Chrome-racefix (fokusfördröjning) för att undvika “no file selected”.
- Profilmedia: `/studio/profile/media` listar lärarens lektionsmedia + LiveKit-inspelningar och låter läraren skapa/uppdatera/ta bort presenterade poster (titel, beskrivning, omslag, publiceringsstatus). Publik vy använder `/community/teachers/{id}/media`, visar “Utvalt innehåll” med CTA:s samt inline-spelare (audio/video) för signerade resurser.
- API `/courses/me`: 500-fel åtgärdat. Query och modeller justerade för `video_url` och `created_by` i Course-schemat; indentering och fält synkade.
- Backend: `list_my_courses` returnerar nu `video_url` och `created_by` enligt schema, med bakåtkompatibilitet när kolumner saknas.

CI-pipelines (2025-10-25)
-------------------------

- **Backend CI** (`.github/workflows/backend-ci.yml`): Poetry-install, `ruff check`, `flake8`, `mypy` (nu täcker `app/utils`, `app/routes/api_services.py`, `app/repositories/services.py`), `pytest --cov` (publicerar `coverage.xml`) och `pip-audit`. Kräver inga hemligheter; kör på Python 3.11 och jobbar i `backend/`.
- **Flutter CI** (`.github/workflows/flutter.yml`): kör `flutter analyze`, `flutter test` och `flutter test integration_test`. QA-smoke-jobbet läser credentials/DB-url från GitHub Secrets med fallback till lokala dummyvärden.
- **Web CI** (`.github/workflows/web-ci.yml`): Node 20, `npm ci`, `npm run lint`, `npx tsc --noEmit` och `npm test` (Vitest). Inga extra hemligheter behövs eftersom landningssidan är statisk.

QA-smoke GitHub Secrets (`Settings → Secrets and variables → Actions`):

- `QA_API_BASE_URL`
- `QA_TEACHER_EMAIL` / `QA_TEACHER_PASSWORD`
- `QA_STUDENT_EMAIL` / `QA_STUDENT_PASSWORD`
- `QA_DATABASE_URL`
- `QA_DB_PASSWORD`

Workflown faller tillbaka på localhost + seed-konton om någon av hemligheterna saknas.

HTTPS-policy per plattform (2025-10-15)
---------------------------------------

- **Android:** Dev-emulatorn tillåts via `network_security_config.xml` (klartext mot `10.0.2.2`/`localhost`). Release-builds ska använda `https://` för API och media; `lib/main.dart` loggar varning om `API_BASE_URL` är HTTP i release.
- **iOS/macOS:** ATS (App Transport Security) är oförändrat → endast HTTPS. Undantag kräver explicita `NSExceptionDomains`; undvik i prod.
- **Web/Desktop:** Lokalt utvecklingsläge kör HTTP men prod ska serveras via HTTPS för PWA/service workers. Följ `docs/local_backend_setup.md` för lokala overrides.
- **Backend-media:** Extern leverans ska ske via `/media/stream/{token}` (signeras av backend). `/studio/media/{id}` är legacy och ska vara avstängt i prod (`MEDIA_ALLOW_LEGACY_MEDIA=false`).
- **Klienter:** `AppNetworkImage` injicerar auth-header på mobil/desktop vilket kräver HTTPS (speciellt på iOS). Flutter varnar i release om HTTP används.
- **Snabbsanity:** Kör  
  `select id, title, thumbnail_url from app.services where thumbnail_url is not null and thumbnail_url !~ '^https://';`  
  inför release. Resultatet ska vara tomt; annars korrigeras URL:er.

Tester/QA

- Nya tester: `backend/tests/test_courses_me.py` validerar form och fält på `/courses/me`.
- QA-skript: `scripts/qa_teacher_smoke.py` kör grönt (login, avatar, kurs/modul/lektion, media, quiz, studentvy).
- Manuell: `GET /courses/me` svarar 200 med inskrivna kurser.
- Nytt test: `backend/tests/test_courses_enroll.py` registrerar temporär användare, enrolar gratis intro-kurs och verifierar att `/courses/me` innehåller kursen.

Körning

- Backend dev: `make backend.dev`
- Reset DB: `./scripts/reset_backend.sh`
- Enskilt test: `(cd backend && poetry run pytest -q tests/test_courses_me.py)`
- Alla backendtester: `(cd backend && poetry run pytest)`

Nice-to-haves

- [x] Serialisera audio-embeds till `<audio>` vid persistens för icke-Quill-visare (2025-10-17) – backend normaliserar Quill-embeds via `serialize_audio_embeds` innan lektioner sparas.
- [x] Lägg till test som enrolar ny användare i gratis introkurs och asserter att `/courses/me` inkluderar den (2025-10-17) – se `backend/tests/test_courses_me.py::test_courses_me_updates_after_free_intro_enrollment`.
