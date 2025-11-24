# 1) Datamodell & backend (bokningar)

**Tabeller (förslag):**

- `sessions` (id, teacher_id, title, description, start_at, end_at, capacity, price_cents, currency, visibility: draft/published, recording_url, created_at, updated_at)
- `session_slots` (id, session_id, start_at, end_at, seats_total, seats_taken)
- `orders` (id, user_id, session_id/null, course_id/null, type: one_off/subscription, amount_cents, currency, status, stripe_payment_intent, stripe_subscription, connected_account_id, created_at, updated_at)
- `teachers` (id, profile_id, stripe_connect_account_id, payout_split_pct, onboarded_at)

**API-endpoints (min):**

- `POST /studio/sessions` (skapa/uppdatera)
- `GET /studio/sessions?status=published` (för landing/home)
- `GET /sessions/:id/slots` (tillgängliga tider)
- `POST /checkout/session` (server: skapar PaymentIntent **eller** Subscription, se §3–§4)
- `POST /webhooks/stripe` (tar emot livscykel-events, se §7)

---

# 2) Kalender-UI (måninspirerad)

**Lärar-studio**

- Månfaser som “accent”: använd månfase-ikon i header per dag/vecka, och tunn glas-blur panel (glassmorphism) för att matcha resten av UI:t.
- “Dra-och-släpp” block för att skapa slots (30/45/60 min) → sparas till `session_slots`.

**Elev**

- Månads/veckovy: markera **kommande** slots (grön), **nästan full** (gul), **full** (grå).
- Klick på slot → modalen “Boka nu” → **inbäddad Stripe-betalning** (se §3).

---

# 3) Engångsköp (session/kurs) – **inbäddad Stripe-skärm**

Använd **Payment Element** (en inbäddningsbar Stripe-komponent som stöder 100+ betalmetoder globalt, inkl. kort, Klarna och PayPal). Det är Stripes rekommenderade, moderna väg jämfört med gamla Card Element. ([Stripe Docs][1])

**Flöde (one-off):**

1. Server: `POST /checkout/session`

   - Skapa **PaymentIntent** med `amount`, `currency`, `automatic_payment_methods: {enabled: true}`.
   - (Marketplace) Lägg till **destination charge**: `transfer_data[destination]=<teacher_connect_id>` + `application_fee_amount` (din plattformsandel). ([Stripe Docs][2])

2. Klient: rendera **Payment Element** med `client_secret` → visar lokalt relevanta metoder.

   - **PayPal** visas som ett alternativ; vid val gör Stripe automatisk redirect till PayPal och tillbaka till er (ingen extra integration). ([Stripe][3])
   - **Klarna** exponeras också via Payment Element om valutas/land stöds; dess options styrs via PaymentIntent-fält (API stöder Klarna/PayPal options). ([Stripe Docs][4])

3. Bekräfta; Payment Element hanterar validering & fel.
4. Webhook: `payment_intent.succeeded` → markera order “paid”, boka plats, skicka kvitto.

> Om du hellre kör en färdig Stripe-sida: **Checkout** funkar men är en redirect-lösning. Ni vill ha **inbäddad** → välj Payment Element. (Jämförelsen finns här.) ([Stripe Docs][5])

---

# 4) Prenumeration vid kontoskapande (med inbäddad form)

Använd **Stripe Billing + Payment Element** för att skapa en **subscription** (Produkt/Price i Stripe) med valfri provperiod. Guiden “Build a subscriptions integration” visar just detta upplägg (inbäddad form, inte redirect). ([Stripe Docs][6])

**Flöde (subscription):**

1. Server: skapa **Customer** om ny.
2. Skapa **Subscription** (items = valt price). Vid behov använd **SetupIntent**/default_payment_method för framtida debiteringar (krav för prenumerationer). ([Stripe Docs][7])
3. Klient: Payment Element samlar in betalmetod (3DS/SCA hanteras av Stripe).
4. Webhook: `invoice.paid`, `customer.subscription.created/updated` → aktivera elevens medlemskap.

---

# 5) Betalmetoder (kort + PayPal + Klarna)

- **Payment Element** exponerar automatiskt tillgängliga metoder (kort, wallets, BNPL etc.) baserat på område/valuta; PayPal och Klarna är stödja via samma integration (inga separata SDK-flöden behövs). ([Stripe Docs][1])
- **PayPal**: kund landar hos PayPal, väljer källa, returneras till er och Payment Element färdigställer betalningen. ([Stripe Docs][8])
- **Klarna**: presenteras när belopp/land/valuta uppfyller kraven; konfig via PaymentIntent/Payment Element. ([Stripe Docs][4])
- Vill ni ha “snabblistor” högst upp (Apple Pay/Google Pay/Link/PayPal/Klarna) kan ni även addera **Express Checkout Element** som layout-optimerar ordning på metoderna. ([Stripe Docs][9])

---

# 6) Marketplace-utbetalningar till lärare (Stripe Connect)

- Onboarda lärare som **Express-konton** (konto-länkar).
- Använd **destination charges**: skapa betalningen på plattformskontot; sätt `transfer_data[destination]` (lärare) och `application_fee_amount` (er plattformsavgift). Stripe överför automatiskt nettot till läraren efter capture. ([Stripe Docs][10])
- Sätt **payout schedule** och **statement descriptor prefix** per lärare om ni vill (för tydlighet på deras sidan).

---

# 7) Webhooks (minsta krav)

Registrera endpoint `POST /webhooks/stripe` (signerad):

- **Engångsköp**: `payment_intent.succeeded`, `payment_intent.payment_failed`
- **Prenumeration**: `invoice.paid`, `invoice.payment_failed`, `customer.subscription.updated|deleted`
- **Payouts/Connect**: `charge.succeeded` (med `transfer_data`), `transfer.created`, ev. `payout.paid`
- Uppdatera `orders` och `sessions.seats_taken`, skicka e-postkvitton.

---

# 8) UI/UX detaljer (inbäddad betalning)

- **Glass-morphism** runt Payment Element (blur + translucency), enhetligt med övriga appen.
- **Slot-val → betalpanel** i samma modal/sida (ingen extern redirect).
- **“Säker betalning”-rad**: visa kortikoner + PayPal + Klarna när Payment Element laddats.
- **Kvittosida**: visa sammanfattning + länk till session/kurs/recording.

---

# 9) Skatt, SCA och kvitton

- **EU/PSD2 (SCA/3DS)**: Payment Element hanterar utmaningar automatiskt där det krävs.
- **MOMS/VAT**: aktivera Stripe Tax om ni vill automatisera beräkning & rapport (frivilligt i första iterationen).
- **Kvitton**: sätt `receipt_email` eller använd Stripes automatiska e-post; lägg in **support**-uppgifter & **statement descriptor** (du har `AVELI.APP` – bra).

---

# 10) Publicering på landing & home

- `GET /studio/sessions?status=published&from=now` → landing visar **kommande** (sorterade efter starttid).
- På **home** för inloggad elev: överst “Nästa live”, under “Rekommenderade kurser”, längre ner “Tidigare sändningar” (uppladdade recording-URL:er).
- Gamla sändningar **tas bort från översta delen** och hamnar i “Tidigare sändningar”.

---

# 11) Implementations-checklista (i ordning)

**A. Stripe konfiguration**

- [ ] Skapa **Products/Prices** för: i) drop-in-session (ex. 20–60 min), ii) kurser (engång), iii) **medlemskap** (prenumeration).
- [ ] Aktivera **PayPal** & **Klarna** i Dashboard (Payments → Payment methods). ([Stripe][3])
- [ ] Skapa **Connect**-inställningar (Express onboarding).

**B. Backend**

- [ ] Endpoints i §1 + webhook i §7.
- [ ] **One-off**: POST skapar PaymentIntent (+ destination charge & fee). ([Stripe Docs][2])
- [ ] **Subscription**: POST skapar Customer + Subscription (Payment Element för PM-insamling). ([Stripe Docs][6])
- [ ] Upprätta kvittomail & orderstatusar.

**C. Frontend**

- [ ] **Kalender-UI** (månfaser, glass-kort).
- [ ] **Payment Element** (inbäddad) för session/kurs/prenumeration; visa metoder dynamiskt. ([Stripe Docs][1])
- [ ] Success/fail-views + “Gå till min bokning”.

**D. Kvalitet**

- [ ] Testa **SCA** (3DS challenge).
- [ ] Testa **PayPal-flödet** (redirect tillbaka). ([Stripe Docs][8])
- [ ] Testa **Klarna** i SEK/EUR sandbox. ([Stripe Docs][4])
- [ ] Testa **Connect**: order med fee & teacher-payout. ([Stripe Docs][10])

---

# 12) Kodstommar (kort)

**PaymentIntent (server, one-off + Connect destination charge):**

```ts
// Node/Express pseudo
const paymentIntent = await stripe.paymentIntents.create({
  amount,
  currency,
  automatic_payment_methods: { enabled: true },
  transfer_data: { destination: teacher_connect_id }, // utbetalning till läraren
  application_fee_amount: platformFeeAmount, // er andel
  metadata: { session_id, user_id },
});
```

(Detta är “destination charges” enligt Stripe Connect-mönstret.) ([Stripe Docs][2])

**Subscription (server):**

```ts
const customer = await stripe.customers.create({
  email,
  metadata: { user_id },
});
const subscription = await stripe.subscriptions.create({
  customer: customer.id,
  items: [{ price: PRICE_ID }],
  expand: ["latest_invoice.payment_intent"],
});
```

(Integrationen byggs med Payment Element enligt Stripe Billing-guiden.) ([Stripe Docs][6])

**Client (web) – Payment Element init:**

```js
const elements = stripe.elements({ clientSecret });
const paymentElement = elements.create("payment");
paymentElement.mount("#payment-element");
```

(Payment Element – inbäddad UI, visar kort/PayPal/Klarna där det stöds.) ([Stripe Docs][1])

---

# 13) Nästa konkreta steg för oss

1. Jag sätter upp **Products/Prices**-matris (session 30/45/60, kurs, medlemskap) + Connect-flöde (Express).
2. Vi lägger in **/checkout/session** (PaymentIntent + destination charge) och **/checkout/subscription** (Billing + Payment Element).
3. Jag skickar **Codex-prompter** för:

   - måninspirerad kalender-UI (glass),
   - inbäddad Payment Element-panel,
   - landing/home-listor (endast kommande högst upp; tidigare sändningar i egen sektion).

# 14) Arbetsfördelning (Codex vs Oden)

**Codex – allt vi kan bygga lokalt i repo**

- [ ] Databas & modeller: skriv migration `backend/migrations/sql/025_sessions_and_orders.sql` för `sessions`, `session_slots`, `orders`-utökningar och `teachers`-Connectfält; uppdatera `backend/app/repositories/*` och `schemas.py` så FastAPI-exponeringen matchar datamodellen.
- [ ] Backend-API: implementera `routes/studio_sessions.py`, `routes/session_slots.py`, `routes/checkout.py` och `routes/stripe_webhooks.py`; koppla mot nya service-lager i `app/services/booking_service.py` och `app/services/checkout_service.py`.
- [ ] Stripe Connect i backend: skapa endpoints för Express-onboarding + statuspolling (`routes/connect.py`) och logik i `services/connect_service.py`, så vi kan initiera/länka konton innan användaren gjort något i Dashboard.
- [ ] Flutter UI – studio & elev: bygga månfaskalendern i `lib/features/studio/scheduling` (drag-and-drop slots) samt elevens månads/veckovy i `lib/features/home` + `lib/features/payments`, inklusive modal med inbäddad Payment Element via `flutter_stripe`.
- [ ] Flutter UI – checkout + kvitto: implementera Payment Element wrapper (glassmorphism) i `lib/features/payments/widgets`, success/fail-vyer och “Gå till min bokning”-flöde som navigerar till `lib/features/courses`/`seminars`.
- [ ] Webhooks & orderlivscykeltester: lägga till enhetstester i `backend/tests/test_checkout.py` och `test_webhooks.py`, samt end-to-end widget-/integrationstester i `integration_test` som simulerar kort, PayPal och Klarna.
- [ ] Observability & tooling: instrumentera loggar/metrics för checkout (`app/logging_utils.py`, `app/metrics.py`) och uppdatera `scripts/dev_backend.sh` så nya tjänster startas med rätt env.

**Oden – Stripe.com & externa paneler**

- [ ] Slutför Stripe Dashboard-konfig (Products/Prices, Payment methods inklusive PayPal/Klarna, Connect Express, webhook endpoint + secrets).
- [ ] Lägg in Apple Pay/Klarna/PayPal-branding, statement descriptor och Stripe Tax (om vi kör moms automatiskt).
- [ ] Hantera kontoverifiering för egna lärarkonton i Dashboard (så våra testlärare får `charges_enabled`/`payouts_enabled`).
- [ ] Dela ut API-nycklar, webhook-secret och ev. `STRIPE_CONNECT_CLIENT_ID` till oss via `.env` (test + live).
- [ ] Stå upp testlänkar till Stripe Checkout/Customer Portal om vi senare behöver fallback, samt verifiera att payout-scheman/kontoutdrag matchar våra krav.

# 15) Koppla kalender → publicering → elevbokning → Stripe

**Delmoment**

- lärarens kalender (från Prompt 1),
- session-publicering,
- bokning för eleven,
- Stripe-betalning (från Prompt 2).

---

## 🔍 Vad Stripe-vyn betyder just nu

1️⃣ **Ersättningsansvar för återbetalningar**

> Du accepterar att Aveli (plattformen) är ansvarig för ev. återbetalningar/chargebacks.
> → Det är korrekt – du agerar som *plattform* i ett marketplace (Stripe Connect).

2️⃣ **Bekräfta integrationsval**
Du bekräftar tre viktiga punkter:

* **Betalningsflöde:** “Köparna handlar av dig / Säljarna säljer via dig”
  ✅ Rätt för en marketplace-modell (destination charges).
* **Kontohantering:** Du använder inbäddade komponenter för att lärare ska kunna skapa/hantera Stripe-konton direkt i din app.
  ✅ Vi använder `accountLink`-flödet (Express Connect).
* **Ersättningsansvar:** samma som ovan, du står som betalningsansvarig mot kund.

👉 Klicka “Fortsätt”, och Stripe aktiverar **Connect Express**.
Efter det får du **dina live-nycklar** (de som ska in i `.env`):

```
STRIPE_CONNECT_CLIENT_ID=
STRIPE_PUBLISHABLE_KEY=
STRIPE_SECRET_KEY=
```

---

## 🧠 Codex-Prompt #3 — Koppla samman Kalender + Booking + Stripe

````
🎯 Objective:
Connect the teacher’s StudioCalendar (Prompt 1) with the embedded PaymentPanel (Prompt 2).
When a teacher creates or publishes a session, it becomes visible to students. 
Students can book an available time slot → triggers the Stripe PaymentPanel with the correct session price.

📂 Target files:
- lib/features/studio/widgets/studio_calendar.dart
- lib/features/seminars/presentation/seminar_booking_page.dart
- lib/features/payments/widgets/payment_panel.dart
- lib/features/payments/services/stripe_service.dart

---

⚙️ Functional Flow:

1️⃣ Teacher creates & publishes session
- StudioCalendar already stores sessions locally or via API.
- Extend the session model to include: `id`, `title`, `description`, `price`, `duration`, `teacher_id`, `stripe_price_id`.

2️⃣ Backend exposes:
   - `GET /sessions?status=published` → list available sessions for students.
   - `POST /checkout/session` → returns Stripe PaymentIntent `client_secret` for a given `session_id`.

3️⃣ Student booking UI:
Create `SeminarBookingPage` (new screen):
```dart
GlassContainer(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(session.title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(session.description, style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 20),
      Text("Pris: ${session.price} SEK", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: () async {
          final clientSecret = await StripeService(baseUrl).createPaymentIntent(
            amount: session.price,
            currency: 'sek',
            type: 'session',
          );
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => PaymentPanel(
              clientSecret: clientSecret,
              onPaymentSuccess: () => _onPaymentSuccess(context),
            ),
          ));
        },
        child: const Text("Boka & Betala"),
      ),
    ],
  ),
);
```

4️⃣ On payment success:

```dart
void _onPaymentSuccess(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => GlassContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 12),
          const Text("Betalning genomförd!", style: TextStyle(fontSize: 20)),
          const SizedBox(height: 8),
          Text("Du har nu bokat din plats i ${session.title}."),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            child: const Text("Tillbaka till hem"),
          ),
        ],
      ),
    ),
  );
}
```

---

💡 UI style:

* Continue glass-blur across both teacher & student flows.
* Use moon-phase icon for session status (🌑 = draft, 🌓 = published, 🌕 = full).
* “Boka & Betala” button uses gradient border like in Prompt 2.

---

✅ Test steps:

1. Teacher adds & publishes a session in StudioCalendar.
2. Student opens SeminarBookingPage → sees active sessions.
3. Click “Boka & Betala” → embedded Payment Element loads inside PaymentPanel.
4. Complete test payment with Stripe test-kort → webhook returns success.
5. Verify booking confirmation dialog & Stripe Dashboard charge.

---

Expected outcome:

* Teachers manage sessions directly via the lunar calendar.
* Students browse & book available times.
* Payment flow uses the same embedded Stripe Payment Element (Visa, Mastercard, PayPal, Klarna).
* On success, the order is recorded and confirmation UI appears within the glass-styled interface.

```
