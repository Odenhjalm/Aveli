+# projectAPP — Master Prompt
+
+## 0) Mission & Tone
+Bygg en svensk, vacker och modern mobilapp i Flutter för andlig undervisning och community.  
+Känsla: **lugn, proffsig, magisk** – men **realistisk**, **snabbrörlig**, och **kommersiellt hållbar**.
+
+## 1) Tech Stack (måste)
+- **Flutter (Dart 3)** – Riverpod för state, go_router för navigation, Material 3.
+- **Supabase** – Auth (PKCE), Postgres + RLS, Storage, RPC/Edge Functions.
+- **Stripe** – betalningar (Checkout/PaymentSheet) + webhook (Supabase Edge Function).
+- **Firebase** – FCM (push), Analytics, Remote Config, Crashlytics.
+- **Gemini** – intern AI-kommandopalett (”Lovable-känsla”) som genererar JSON-DSL → renderas till UI.
+
+## 2) Appens nivåer & logik
+**Free Tier (alla)**  
+– 5 gratis kurser (introduktion). Vid första uppstarten kan man ”Hoppa över betalning” → kvoten räknas lokalt + i DB.
+
+**Course Participant (certifiering)**  
+– Köper certifiering (t.ex. ”Aspirerande Vit Magiker”) → låser upp nästa kursnivå & förhandskrav till community.
+
+**Member (community)**  
+– Certifierade kan skapa/dela: ceremonier, meditationscirklar, tarot, erbjudanden/tjänster (IRL eller video/voice/chat).  
+– P2P-betalningar via plattformen (ca 10% avgift).  
+– Profil visar bio, foto, pågående/avslutade kurser & cert.  
+– Pedagogiskt krav: första kursen som medlem innehåller en uppgift att publicera en egen tjänst (för att lära UI + betalflöde).
+
+## 3) Lärar-Studio – `/studio` (svensk UI)
+- **Route guard:** endast teacher eller admin. Andra ser svensk info + knapp ”Ansök som lärare” → rad i `public.teacher_requests(note)`.
+- **Sidomeny:** Mina kurser, Moduler & Lektioner, Media, Inställningar.
+- **Mina kurser:** List + skapa/redigera (title, branch, cover_url, price_cents, is_published, is_free_intro). Visa endast `teacher_id = auth.user`.
+- **Moduler & Lektioner:** nested editor. Moduler (title, index). I varje modul: CRUD lektioner (title, index, rich text bound till `lessons.content` JSON, `free_preview` toggle). Optimistic UI.
+- **Media:** ladda upp filer knutna till lektion → Supabase Storage: bucket `public-media (${user.id}/...)` och ev. `private-media`.  
+  Efter uppladdning: insert i `public.lesson_media {lesson_id, type, storage_path, is_public}`. Visa preview + kopierbar URL för public.
+- **Inställningar:** hantera `teacher_directory`: display_name, headline, specialties (text[]), price_cents, avatar_url, is_accepting. Upsert på `user_id=auth.user`.
+- **RLS:** läsa/skriva kurser/moduler/lektioner endast när `teacher_id = auth.uid()`.  
+  `teacher_directory` läs publikt, men uppdatera endast egen rad.  
+  När `lesson.free_preview=false` → lektionen dold för icke-behöriga (svensk förklaring i UI).
+
+## 4) Tarot, Bokningar, Messaging, Admin
+**Tarot-läsningar**  
+– Student skapar förfrågan (fråga + leveranssätt: text/voice/video).  
+– Betalning (Stripe) innan leverans.  
+– Lärare levererar svar + markerar status: Pending → In progress → Delivered.
+
+**Privata sessioner (bokning)**  
+– Lärare publicerar tider (slotar) med pris & längd.  
+– Student bokar & betalar.  
+– Auto-bekräftelse, avbokning/ombokning, ICS-inbjudan mailas båda.
+
+**Messaging**  
+– Direktmeddelanden (student↔lärare).  
+– Kurs-trådar.  
+– Notiser vid nya meddelanden.
+
+**Admin**  
+– Dashboard: godkänn lärare, moderera innehåll, hantera återköp.  
+– Översikt: alla kurser, bokningar, tarot, betalningar.
+
+**Legal & GDPR**  
+– Sidor: Integritetspolicy och Villkor (svenska).  
+– Profil: Exportera data (zip) och Radera konto.
+
+## 5) Datamodell (Supabase — tabeller & nyckelfält)
+- `profiles(id uuid PK=auth.uid, display_name, bio, photo_url, role enum, created_at)`
+- `app_config(id=1, free_course_limit int default 5, platform_fee_pct numeric default 10)`
+- `courses(id, teacher_id, title, branch, description, cover_url, price_cents, is_published bool, is_free_intro bool, created_at)`
+- `modules(id, course_id, title, index)`
+- `lessons(id, module_id, title, index, content jsonb, free_preview bool, media_count int)`
+- `lesson_media(id, lesson_id, type enum{image,video,audio,pdf}, storage_path, is_public bool, created_at)`
+- `enrollments(id, user_id, course_id, status enum{enrolled,completed}, progress int, opened_at)`
+- `certifications(id, user_id, course_id, title, issued_at, verified_by, proof_url)`
+- `memberships(id, user_id, status enum{none,active,expired}, plan enum{free,member}, started_at, expires_at)`
+- `events(id, host_user_id, title, description, mode enum{irl,video,voice,chat}, start_at, end_at, location, price_cents, requires_cert bool, created_at)`
+- `services(id, provider_user_id, title, description, price_cents, duration_min, requires_cert bool, active bool)`
+- `orders(id, user_id, type enum{certification,membership,service,event,tarot,booking}, ref_id uuid, amount_cents, platform_fee_cents, status enum{pending,paid,failed,refunded}, payment_ref, created_at)`
+- `teacher_requests(id, user_id, note, created_at, status enum{pending,approved,rejected})`
+- `teacher_directory(user_id PK, display_name, headline, specialties text[], price_cents, avatar_url, is_accepting bool, updated_at)`
+- **Tarot:** `tarot_requests(id, student_id, teacher_id, question, delivery enum{text,voice,video}, status enum{pending,in_progress,delivered}, order_id, answer_text, answer_media_path, created_at, delivered_at)`
+- **Booking:**  
+  `teacher_slots(id, teacher_id, starts_at, ends_at, price_cents, duration_min, notes, is_published bool)`  
+  `bookings(id, slot_id, student_id, status enum{reserved,paid,cancelled,completed}, order_id, created_at)`
+
+### RLS (exempelprinciper – implementera fullständigt)
+`profiles`: select alla; update endast egen rad.  
+`courses/modules/lessons`: write endast när `teacher_id=auth.uid()` eller admin.  
+`teacher_directory`: select publik; upsert endast egen `user_id`.  
+`orders`: insert/select endast av ägaren; status ändras via säker funktion/webhook.  
+`tarot_requests`: select ägare (student eller teacher_id), admin full.  
+`teacher_slots`: write endast ägare (teacher), select alla.  
+`bookings`: select ägare (student/teacher), admin full.
+
+### Funktioner/RPC (minst)
+- `free_consumed_count(user_id) → int`
+- `can_access_course(user_id, course_id) → bool` (is_free_intro + free_limit + cert + membership)
+- `start_order(user_id, type, ref_id, amount) →` skapar order (pending)
+- `complete_order(order_id, payment_ref) →` sätter paid, triggar cert/membership/booking-aktivering
+
+---
+
+## Leveransregler för agenten
+1. Svara med **giltig unified diff** eller kompletta filer (ingen extra text).  
+2. Skriv migrations, seeds, RLS-regler och testdata när det behövs.  
+3. Respektera **Material 3**, **Riverpod**, **go_router**.  
+4. Säkra **Supabase Auth (PKCE)**, RLS och serverfunktioner.  
+5. Stripe-flöden via edge function-webhook; logga status/kvittodata.  
+6. Dokumentera körkommandon i PR-beskrivningen.
+

