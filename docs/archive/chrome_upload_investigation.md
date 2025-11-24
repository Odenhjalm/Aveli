# Chrome Upload Debug Log

## Översikt
- **Plattform:** Flutter web i Chrome (via `flutter run -d chrome`)
- **Funktion:** Kurseditorns mediauppladdning (bild/video) + landningssidans kurskort
- **Senaste åtgärder:** Uppdaterad webbpickers handler (`file_picker_web_html.dart`) så att den väntar på filval och returnerar MIME-typ, men användaren rapporterar fortfarande “inget händer”.

## Observerade symptom
- Filväljaren öppnas i Chrome men ingen uppladdning sker efter att fil valts.
- `flutter`-konsolen visar upprepade 404-fel mot `http://127.0.0.1:8000/studio/media/6ad456b5-b599-4eaa-95ed-52c29f72a801`.
- Landningssidan visar RenderFlex-varningar och varningsband när samma 404-filer renderas.

## Backendloggar
```text
$ tail -n 40 backend_uvicorn.log
psycopg.errors.UndefinedColumn: column "requires_cert" does not exist
LINE 3:                    requires_cert, certified_area, created_at
                                    ^
...
psycopg.errors.UndefinedColumn: column "video_url" of relation "courses" does not exist
...
psycopg.errors.NotNullViolation: null value in column "price_cents" of relation "courses" violates not-null constraint
```
- Loggen saknar “Media stored”‑rader, vilket betyder att backend aldrig tar emot lyckade POST:ar från Chrome.
- Databasdumpen ligger före nuvarande migreringar (`requires_certification`, `video_url` osv.) → flera endpoints faller med 500.

## Frontendobservations
- Kurseditorn förväntar sig att `studioUploadQueueProvider` triggar UI via Riverpod. Utan backendrespons stannar status på ”Ingen bild vald.”  
- Gridkorten på landing laddar media via `download_url`. När `GET /studio/media/<id>` returnerar 404 visas gul-svart mönster. Dessa poster härstammar från `app.lesson_media`-rader vars filer saknas efter dumpen.

## Rekommenderade verifieringssteg
1. **Database schema sync**
   ```bash
   cd backend
   poetry run alembic upgrade head  # eller make migrate
   ```
   Starta om uvicorn och kontrollera att `list_services`/`create_course` inte längre kastar `UndefinedColumn`.

2. **Rensa trasiga mediaposter**
   ```sql
   SELECT lm.id, lm.lesson_id
   FROM app.lesson_media lm
   LEFT JOIN app.media_objects mo ON mo.id = lm.media_id
   WHERE mo.id IS NULL;
   ```
   Ta bort/ersätt raderna och ladda upp nytt media via studio-UI.

3. **Chrometest**
   - Öppna DevTools → fliken Network, filtrera på `media`.
   - Klicka på “Ladda upp bild” och välj fil.
   - Bekräfta att `POST /studio/lessons/<lesson_id>/media` skickas och får status 200.
   - Övervaka `backend_uvicorn.log` för “Media stored: …”.

4. **Om upload fortfarande inte triggar**
   - Kontrollera DevTools Console för JavaScript-fel (säkerhetsinställningar, CORS, popup-blockering).
   - Notera `_mediaStatus`-texten i UI (ska uppdateras till ”Laddar upp …” direkt efter val).
   - Spara nya loggar i denna fil med tidsstämplar.

## Hypotes
Avbrotten orsakas av att backend inte kan lagra media (DB-schemat saknar kolumner efter dumpen). Eftersom POST:en misslyckas returnerar Flutter `HTTP request failed, statusCode: 404/500`, och UI visar ingen bekräftelse. När migreringarna körs om, och trasiga mediareferenser städas bort, bör Chrome-uppladdningen fungera som på desktop.

## Nästa steg
- Kör migreringarna, starta om backend, rensa invalid media och testa igen.
- Skicka uppdaterade loggar (backend + DevTools) om problem kvarstår.
