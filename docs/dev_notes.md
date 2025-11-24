# Dev-notes – Data & UX

## JSON-konventioner

- **Snake case överallt**: alla backend-responser ska använda snake_case (`app.activities_feed`, `/payments/**`). Nya Dart-modeller ska alltid annoteras med `@JsonSerializable(fieldRename: FieldRename.snake)` och eventuella specialfält ska beskrivas via `@JsonKey`.
- **Typed modeller före `Map`**: använd `json_serializable`-modeller under `lib/data/models/` i stället för att skicka runt ok typade mappar. Om du behöver ad hoc-fält (t.ex. metadata) – addera explicita `Map<String, dynamic>`-fält med `@JsonKey(defaultValue: {})`.
- `CommunityPost`/`CommunityProfile` och `MessageRecord` ligger nu som delade modeller i `lib/data/models/`. Gamla manuella `.fromJson`-implementationer i features har städats bort så alla listor (`postsProvider`, `messagesRepository`, `teacherProfileProvider`, `profileViewProvider`) arbetar med typed objekt.
- **Backend-kommentarer**: kommentera SQL med “RLS-ready” där vi planerar att slå på Supabase-policys, och håll `schema app` i sync via `backend/migrations/sql`. Låt `database/schema.sql` vara den enda sammanslagna versionen.

## Felhantering & feedback

- `AppFailure.from(error)` ger centrala, svenskifierade meddelanden för 400/401/402/403/404/500. Lägg till specialfall i `_localizeDetail` om backend introducerar nya felkoder.
- Använd `showSnack(context, message)` eller `ScaffoldMessenger.of(context)` med global messenger (`main.dart`) för att visa meddelanden.
- HTTP-status → UX
  - **401**: session reset + redirect till `/login?redirect=<current>`, snackbar “Sessionen har gått ut…”.
  - **403**: snackbar “Behörighet saknas…” och hoppa hem från lärar-/adminrutter.
  - **402**: snack i web/Flutter “Betalningen misslyckades…” (fångas i `AppFailure`).
  - **500+**: generisk “Serverfel (status)” och logga detaljer i dev-console.

## UI-mönster

- **Knappar**: använd `bool _isSubmitting` + `CircularProgressIndicator(strokeWidth: 2)` i knappen för login, kurs-publicering och betalningar. Stäng av `onPressed` när `_isSubmitting` eller blockat av RLS/behörighet.
- **Certifierings-gate**: `evaluateCertificationGate` (`lib/features/community/application/certification_gate.dart`) kapslar logiken och används i `ServiceDetailPage`, `TeacherProfilePage` och `HomeDashboardPage`.
  - `ServiceDetailPage` läser `myCertificatesProvider` och styr CTA:n:
    - Inloggad + certifierad → “Boka/Köp”.
    - Inloggad utan cert → knappen avstängd + röd info-text.
    - Utloggad → CTA “Logga in för att boka” + redirect tillbaka.
  - `TeacherProfilePage` och `HomeDashboardPage` återanvänder samma helper – tjänster som kräver certifiering visar låst knapp (med låsikon) och helper-text i listan. Tests: `test/widgets/home_dashboard_gating_test.dart` + `test/features/teacher_profile_page_test.dart`.
- **Auth events**: `main.dart` lyssnar på `authHttpEventsProvider` och signalerar snackbars + navigering. När du lägger till nya guards, koppla in här i stället för ad hoc-navigation i widgets.
- **Läraransökan**: användare kan inte längre skicka in ansökningar via appen (`/studio/apply` är borttagen). Administratörer hanterar nya lärare genom att verifiera certifikat manuellt i backend.

## Kursomslag i backend/assets

- Lägg nya kursbilder i `backend/assets/images/courses/` och döp filerna efter kursens slug (`foundations-of-soulwisdom` → `foundations_of_soulwisdom.png`).
- Kör `dart run tool/generate_course_cover_assets.dart` efter att du lagt in eller bytt namn på filer så uppdateras `CourseCoverAssets` automatiskt.
- Flutter-klienten slår alltid upp `/assets/images/courses/...` via API-basadressen och använder dessa som fallback om kursen saknar `cover_url` från backenden.

## Ljudresurser per kurs

- Lägg kursljud i en undermapp i `backend/assets/audio/` namngiven efter kursens slug (`foundations-of-soulwisdom` → `backend/assets/audio/foundations_of_soulwisdom/`).
- Kör `dart run tool/sync_audio_assets.dart` för att se till att varje kursmapp har en `.gitkeep` (behövs om den blir tom). Skriptet uppdaterar inte längre `pubspec.yaml`.
- Flutter bundlar inte längre ljudfiler; de streamas via backenden (`/assets/audio/...` eller signerade media-URL:er).
- Testet `test/assets/audio_assets_test.dart` säkerställer att ljudet inte oavsiktligt hamnar i Flutter-bundlen.

## Backendberoenden & uppgraderingar

- **`python-multipart`** är tillagd som explicit dependency för att undvika Starlette-varningen om implicit import.
- **`passlib` / `bcrypt`** använder fortfarande CPythons `crypt()` API. Inför Python 3.13 behöver vi uppgradera till en passlib-version som inte förlitar sig på `crypt` (alternativt byta hash-backend), annars får vi `DeprecationWarning`/framtida fel.
- **JWT-tidsstämplar**: använd alltid timezone-aware `datetime` (`datetime.now(timezone.utc)`) vid refresh/token-hantering för att undvika varningar i `python-jose`.

## Tester

- `test/routing/app_router_test.dart` verifierar att GoRouter-resolvern skickar användaren till rätt ruta beroende på auth/roll.
- Nya tester: `test/features/service_detail_page_test.dart` och `test/features/teacher_profile_page_test.dart` täcker certifieringsgates (login CTA, låst knapp utan cert, lyckat köp). Uppdatera dessa vid ändrat copy eller logik.
- Vid nya guarded-rutter: lägg till case i `route_manifest.dart` och uppdatera testen med motsvarande scenario.
- Kör `dart analyze` + `flutter test` innan PR; pre-commit (`make check`) ropar `dart format`, `dart analyze` och Flutter-testerna.
