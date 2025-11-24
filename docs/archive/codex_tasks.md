Here’s the straight summary of what we’ve shaped for Visdom so far:

User Roles & Flow

Guest: kan se öppet innehåll, köpa enstaka kurs med e-post, claima senare till konto.

User: inloggad, kan se events, feed, köpa kurser.

Professional: får rätt att skapa events när krav/cert uppfyllts.

Teacher: godkänns av admin, får skapa kurser.

Admin: du själv, med kontroll över bakgrund, säsongstema och godkännande.

Backend (Supabase)

Fullt SQL-schema för profiles, certificates, pro_requirements/pro_progress, courses/modules/prices, purchases, guest_claim_tokens, events/attendance, posts/follows.

RLS som styr: kurser endast för rätt roller, moduler preview/offentlig, purchases endast egna.

RPCs: ensure_profile(), has_course_access(), claim_purchase(), grant_professional_if_ready(), grant_teacher().

Stripe Edge Functions: create_checkout (skapar session), stripe_webhook (loggar purchase, skapar claim token för guests).

Frontend (Flutter + Riverpod + go_router)

Providers för session, profile, userRole, hasCourseAccess.

Guards i router för att stoppa icke-pro från /events/new och icke-teacher från /teacher/studio.

CourseAccessGate + PaywallPrompt som antingen visar kurs eller öppnar Checkout.

Event på home screen för att skapa event (endast pro/teacher).

Teacher Studio för kurs-CRUD.

Landing med gratis intro-kurser, login-CTA, “köp enstaka kurs”.

Social feed (posts + follows).

Payments & Access

Stripe Checkout via email (även utan konto).

Webhook loggar purchase i Supabase.

Om ingen profil → guest_claim_tokens skapas och skickas via länk.

Claim-flöde: login med e-post → anropa claim_purchase(token, user_id) → access kopplas.

Extra Features

Admin-panel: du kan godkänna certifikat, promota users till teacher, styra visuella teman.

Editor med live preview så kursens utseende syns innan publicering.

Single sign-on (Google/Microsoft/Facebook) kopplat till Stripe för smidigare onboarding.

Share-knapp med rätt formaterade thumbnails för sociala medier.

Möjlighet till karusell eller kort intro-video i delningar för att öka engagemang.





















4) UI-polish & “infinite width” guardrails
Mål

Alla knappar i Row använder Expanded/Flexible (inte width: double.infinity).

Lägg const där möjligt.

Gemensam spacing/typografi ur shared/theme + shared/constants.

Acceptans

Inga “BoxConstraints … Infinity” crasher.

flutter analyze grönt.

Codex-prompt

Sweep all Row button layouts: if a child button or wrapper uses double.infinity width, replace with Expanded(child: Button(...)). Keep spacing with SizedBox(width: 12).
Add const constructors where applicable.
Remove unused imports.
Ensure all snackbars go through showSnack, post-await navigation guarded by `if (!mounted || !context.mounted) return;` (eller motsvarande `context.mounted` i stateless widgets).
Confirm zero use_build_context_synchronously.
Return changed files.

5) Säkerhet & miljö (prod-redo)
Mål

.env endast public client values. Service Role aldrig i app.

oauth_redirect.dart kraschar inte i prod: fallback med tydligt fel + snack.

RLS-policies: checklista för alla tabeller som UI skriver mot.

(Valfritt) .env.prod handling, ex via --dart-define-from-file.

Acceptans

Appen startar även om env saknas → visar snackbar & block UI för auth-actions.

Inga hemligheter i repo. .gitignore täcker .env, key.properties.

Codex-prompt

Harden env handling:

In main.dart, load .env and if missing keys, set a global EnvStatus.missing and show a banner/snackbar on the landing page with instructions.

In oauth_redirect.dart, don’t assert-crash on missing env; show snack and keep the app usable (but block auth actions).

Ensure .gitignore contains .env, android/key.properties.
Return changed files.

Status (2025-09-25)
- ✅ Alla use_build_context_synchronously-varningar åtgärdade via explicita `mounted/context.mounted`-kontroller.
- ✅ Säkerhet & miljö: Supabase-konfiguration flaggar tydligt genom envInfo, auth-flöden och abonnemang blockeras när nycklar saknas och visar instruktioner.
- ⚠️ Övrig UI-polish (Expanded/Flexible, const, spacing) återstår.

6) Tester (minst sanity + router + en dataflow)
Mål

3 testkategorier:

Widget smoke: app start, landing render.

Router: guardar bort privat route när utloggad; släpper igenom när inloggad.

Data: repo/provider returns list, UI visar rader (mockad Supabase).

Acceptans

flutter test passerar.

Minst 3 tester som ovan.

Codex-prompt

Add tests:

test/app_smoke_test.dart: pump WisdomApp, expect landing hero present.

test/router_guard_test.dart: mock sessionProvider unauthenticated→expect /login; authenticated→expect /home.

test/courses_list_test.dart: mock coursesProvider returns 2 items→UI renders 2 cards.
Use flutter_test, mocktail.
Return new test files.

7) CI/CD (GitHub Actions)
Status: ✅ Flutter CI (format/analyze/test) & release AppBundle workflows ligger i `.github/workflows/flutter.yml` och `release-android.yml`.

8) Android build (prod)
Status: ✅ Gradle uppdaterad till compileSdk/targetSdk 36, minSdk 23 bibehållen. Manifest har `wisdom://auth-callback` och digital asset links, `flutter build appbundle --release` verifierad.
