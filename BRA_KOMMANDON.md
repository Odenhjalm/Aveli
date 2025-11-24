teacher@wisdom.dev / password123 (lärare)
student@wisdom.dev / password123 (student)
admin@wisdom.dev / password123 (admin)
demo@wisdom.dev / changeme (demo-konto för snabb inlogg)



NYDATABAS DUMP!
set -a; source .env; set +a
bash scripts/dump_all.sh


Starta om FastAPI backend + DB:
cd /home/oden/Wisdom/backend
nohup uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload > ../backend_uvicorn.log 2>&1 &


Till Dev miljö:
python3 -m venv .venv && source .venv/bin/activate


# 1. Kolla vilken process som håller porten
lsof -i :8000

# 2. Döda processen (ersätt PID med det du får från lsof)
kill <PID>

# (om flera processer svarar, kör kill på dem också)

# Om back end saknar postgres kör:
make db.up
# 3. Starta backenden igen
cd ~/Wisdom/backend
poetry run uvicorn app.main:app --reload

Reset DB (idempotent reparationer, views, index mm):
./scripts/reset_backend.sh

Kör backend-tester:
(cd backend && poetry run pytest)

Importera kursinnehåll (text + media) till databasen:
python scripts/import_course.py \
  --base-url http://127.0.0.1:8000 \
  --email teacher@example.com \
  --password teacher123 \
  --manifest /full/path/to/course_manifest.yaml
  [--create-assets-lesson] [--cleanup-duplicates]

Exempelmanifest: `scripts/course_manifest.example.yaml`.
- Stöd för `cover_path`: laddar upp omslagsbild och sätter `cover_url` automatiskt.
  - Lägg till flaggan `--create-assets-lesson` för att skapa en separat modul/lektion (`_Assets`/`_Course Assets`) där omslaget laddas upp, istället för i första lektionen.
  - Lägg till `--cleanup-duplicates` för att automatiskt ta bort dubletter (samma originalfil) på befintliga lektioner.
  - Validera manifest och filer utan att ladda upp något:
    - `python scripts/import_course.py --manifest /path/to/manifest.yaml --base-url http://127.0.0.1:8000 --email x --password y --dry-run`
    - Lägg till `--max-size-mb 100` för att varna om filer >100 MB.

Validera alla manifests i `courses/` (ingen uppladdning):
bash scripts/validate_courses.sh

Bulk-importera alla kurser i `courses/` (ordning styrs av `courses/order.txt`):
python scripts/bulk_import.py --base-url http://127.0.0.1:8000 --email teacher@example.com --password teacher123
  [--create-assets-lesson] [--cleanup-duplicates]

Bulk-validera (ingen uppladdning) via samma verktyg:
python scripts/bulk_import.py --dry-run

Slug-krockar (dry-run, lägg till --apply för att fixa):
python scripts/fix_slug_conflict.py

Signerade media-URL:er (kräver MEDIA_SIGNING_SECRET i backend/.env)
token=$(curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"media_id":"<lesson_media_id>"}' \
  http://127.0.0.1:8000/media/sign | jq -r '.signed_url')
curl -L "http://127.0.0.1:8000${token}" --output media.bin

STARTA ANDRIOD EMULATOR:

flutter emulators --launch Pixel_7_API34
startar telefon:

startar app:
flutter run -d emulator-5554


Github :
gh auth login

git config --global user.name "Odenhjalm"
git config --global user.email "odenhjalm@outlook.com"


git push origin main
