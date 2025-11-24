Ditt mål är att leverera en komplett, robust och framtidssäker implementation av den spirituella utbildningsplattformen enligt blueprinten i AGENT_PROMPT.md och uppföljande tasks (tasks2025-09-25.md, codex_tasks_old.md). Följ instruktionerna nedan utan avvikelser:

Databas och backend

Konsolidera Supabase‑schema till den nya kärnstrukturen (rollersystem med role_v2, certifikat, events, services, bookings, tarot_requests, messages). Migrationsskript ska vara idempotenta, dokumenterade och versionerade.

Säkerställ att RLS‑policys använder public.user_is_teacher()/app.is_teacher() som läser role_v2 och lärar‑certifikat. Utöka eller ersätt policyn i storage.objects så att uppladdning endast kräver lärare‑/admin‑roll.

Implementera och testa RPC‑funktionerna free_consumed_count, can_access_course, start_order, complete_order enligt blueprinten.

Bygg edge‑funktioner för Stripe (checkout, webhook) och signed uploads. Hantera claim‑tokens och metadata.

Flutter‑app

Refaktorera kodbasen till en modulär struktur (features/<feature>), använd Riverpod för state‑hantering och go_router med tydliga guards. Allas build‑metoder måste skydda context med explicit if (!mounted) return; efter asynkrona operationer.

Uppdatera alla komponenter till Material 3: byt ut Radio/RadioListTile, ElevatedButton m.m. enligt gällande API. Konfigurera en gemensam ThemeData(useMaterial3: true).

Implementera providers för session/roll, CourseAccessGate och PaywallPrompt. Se till att kursvyer, händelser och studiosidor respekterar rollen (Free, Course participant, Member).

Städa bort gammal “andlig_app”-kod, byt ut context.helper‑anrop mot standardiserade mönster och använd const där det är möjligt.

Funktionella moduler

Implementera teacher directory, booking av tjänster och events, samt tarot‑flödet. Alla bookings och meddelanden ska använda realtidskanaler med RLS‑skydd.

Bygg sök‑ och rekommendationsfunktioner med Supabase fulltext eller annan lämplig teknik.

Lägg till caching/offline‑stöd och enhetstester för kritiska flöden.

CI/CD och kvalitetsarbete

Skapa en CI‑pipeline (GitHub Actions) som kör flutter analyze, flutter test, formatkontroll och builds för Android.

Lägg till testsvit för backend (via Supabase CLI) och frontend.

Dokumentera installations‑ och releaseprocesser samt lägg till manualer i repositoryt.

Leverans och dokumentation

Leverera fullständiga kodfiler och migrationsfiler i en commit. Inga diffar eller partiella utdrag – ge alltid hela, körbara versioner.

Uppdatera README och planeringsfiler med utfört arbete och nästa steg.

Svara inte med förklaringar; koden och dokumentationen ska tala för sig själv.