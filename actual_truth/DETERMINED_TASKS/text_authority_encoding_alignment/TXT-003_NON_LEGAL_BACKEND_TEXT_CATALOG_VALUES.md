# TXT-003 Non-Legal Backend Text Catalog Values

TYPE: OWNER
DEPENDS_ON: [TXT-001, TXT-002, TXT-002A]
MODE: execute
STATUS: COMPLETE_FOR_NON_LEGAL_CATALOG_VALUES

This artifact defines canonical Swedish backend-owned text values for eligible
non-legal concrete text IDs from `TXT-002A_CONCRETE_TEXT_CATALOG_MAPPING_REMEDIATION.md`.
It does not change runtime behavior, frontend rendering, backend response
envelopes, DB schema, DB content, email templates, or Stripe behavior.

## 1. Authority Load

Loaded authority inputs:

- `actual_truth/contracts/system_text_authority_contract.md`
- `actual_truth/contracts/backend_text_catalog_contract.md`
- `actual_truth/DETERMINED_TASKS/text_authority_encoding_alignment/TXT-001_TEXT_SURFACE_INVENTORY.md`
- `actual_truth/DETERMINED_TASKS/text_authority_encoding_alignment/TXT-002_TEXT_CATALOG_MAPPING.md`
- `actual_truth/DETERMINED_TASKS/text_authority_encoding_alignment/TXT-002A_CONCRETE_TEXT_CATALOG_MAPPING_REMEDIATION.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- active contracts under `actual_truth/contracts/`

## 2. Catalog Rules

- `value_sv` is the canonical Swedish user-facing value.
- Text IDs are internal identifiers and MUST NOT render as product copy.
- DB-owned content fields remain DB-owned and are not populated here.
- Non-user-facing identifiers remain non-rendered and are not populated here.
- Blocked domains remain blocked and are not populated here.
- All populated values are Swedish-only product copy.
- Values must be delivered by a later backend/runtime cutover task before UI
  compliance can be claimed.

## 3. Provenance Codes

| Code | Governing basis |
|---|---|
| `P_AUTH` | `TXT-002A`, `auth_onboarding_contract.md`, `auth_onboarding_failure_contract.md` |
| `P_ONBOARDING` | `TXT-002A`, `auth_onboarding_contract.md`, `onboarding_entry_authority_contract.md`, `profile_projection_contract.md` |
| `P_PROFILE` | `TXT-002A`, `profile_projection_contract.md`, `system_text_authority_contract.md` |
| `P_CHECKOUT` | `TXT-002A`, `aveli_embedded_checkout_spec.md`, `commerce_membership_contract.md` |
| `P_HOME_COMMUNITY` | `TXT-002A`, `system_text_authority_contract.md`, `Aveli_System_Decisions.md` |
| `P_COURSE` | `TXT-002A`, `course_public_surface_contract.md`, `course_lesson_editor_contract.md`, `Aveli_System_Decisions.md` |
| `P_STUDIO` | `TXT-002A`, `course_lesson_editor_contract.md`, `media_unified_authority_contract.md` |
| `P_ADMIN` | `TXT-002A`, `auth_onboarding_contract.md`, `onboarding_teacher_rights_contract.md` |
| `P_MEDIA` | `TXT-002A`, `media_unified_authority_contract.md`, `media_lifecycle_contract.md` |
| `P_EMAIL` | `TXT-002A`, `auth_onboarding_contract.md`, `auth_onboarding_failure_contract.md` |
| `P_GLOBAL` | `TXT-002A`, `system_text_authority_contract.md`, `Aveli_System_Decisions.md` |

## 4. Populated Values

### Auth

| text_id | authority_class | value_sv | provenance |
|---|---|---|---|
| `auth.login.title` | `contract_text` | `Logga in` | `P_AUTH` |
| `auth.login.email_label` | `contract_text` | `E-postadress` | `P_AUTH` |
| `auth.login.password_label` | `contract_text` | `Lösenord` | `P_AUTH` |
| `auth.login.submit_action` | `contract_text` | `Logga in` | `P_AUTH` |
| `auth.login.forgot_password_action` | `contract_text` | `Glömt lösenord?` | `P_AUTH` |
| `auth.login.signup_action` | `contract_text` | `Skapa konto` | `P_AUTH` |
| `auth.login.loading_status` | `backend_status_text` | `Loggar in...` | `P_AUTH` |
| `auth.login.success_status` | `backend_status_text` | `Du är inloggad.` | `P_AUTH` |
| `auth.signup.title` | `contract_text` | `Skapa konto` | `P_AUTH` |
| `auth.signup.email_label` | `contract_text` | `E-postadress` | `P_AUTH` |
| `auth.signup.password_label` | `contract_text` | `Lösenord` | `P_AUTH` |
| `auth.signup.submit_action` | `contract_text` | `Skapa konto` | `P_AUTH` |
| `auth.signup.login_action` | `contract_text` | `Jag har redan ett konto` | `P_AUTH` |
| `auth.signup.loading_status` | `backend_status_text` | `Skapar konto...` | `P_AUTH` |
| `auth.signup.success_status` | `backend_status_text` | `Kontot är skapat.` | `P_AUTH` |
| `auth.password.forgot.title` | `contract_text` | `Återställ lösenord` | `P_AUTH` |
| `auth.password.forgot.email_label` | `contract_text` | `E-postadress` | `P_AUTH` |
| `auth.password.forgot.submit_action` | `contract_text` | `Skicka återställningslänk` | `P_AUTH` |
| `auth.password.forgot.loading_status` | `backend_status_text` | `Skickar återställningslänk...` | `P_AUTH` |
| `auth.password.forgot.sent_status` | `backend_status_text` | `Om adressen finns hos oss skickas en återställningslänk.` | `P_AUTH` |
| `auth.password.forgot.retry_action` | `contract_text` | `Skicka igen` | `P_AUTH` |
| `auth.password.reset.title` | `contract_text` | `Välj nytt lösenord` | `P_AUTH` |
| `auth.password.reset.new_password_label` | `contract_text` | `Nytt lösenord` | `P_AUTH` |
| `auth.password.reset.confirm_password_label` | `contract_text` | `Bekräfta lösenord` | `P_AUTH` |
| `auth.password.reset.submit_action` | `contract_text` | `Spara nytt lösenord` | `P_AUTH` |
| `auth.password.reset.loading_status` | `backend_status_text` | `Sparar nytt lösenord...` | `P_AUTH` |
| `auth.password.reset.success_status` | `backend_status_text` | `Lösenordet är uppdaterat.` | `P_AUTH` |
| `auth.email_verification.title` | `contract_text` | `Bekräfta din e-postadress` | `P_AUTH` |
| `auth.email_verification.body` | `contract_text` | `Öppna länken i mejlet för att bekräfta din e-postadress.` | `P_AUTH` |
| `auth.email_verification.resend_action` | `contract_text` | `Skicka bekräftelselänk igen` | `P_AUTH` |
| `auth.email_verification.resending_status` | `backend_status_text` | `Skickar bekräftelselänk...` | `P_AUTH` |
| `auth.email_verification.resent_status` | `backend_status_text` | `Bekräftelselänken är skickad.` | `P_AUTH` |
| `auth.email_verification.verified_status` | `backend_status_text` | `E-postadressen är bekräftad.` | `P_AUTH` |
| `auth.email_verification.already_verified_status` | `backend_status_text` | `E-postadressen är redan bekräftad.` | `P_AUTH` |
| `auth.settings.title` | `contract_text` | `Kontoinställningar` | `P_AUTH` |
| `auth.settings.send_verification_action` | `contract_text` | `Skicka bekräftelselänk` | `P_AUTH` |
| `auth.settings.change_password_action` | `contract_text` | `Byt lösenord` | `P_AUTH` |
| `auth.settings.loading_status` | `backend_status_text` | `Läser in kontoinställningar...` | `P_AUTH` |
| `auth.settings.saved_status` | `backend_status_text` | `Kontoinställningarna är sparade.` | `P_AUTH` |
| `auth.error.invalid_or_expired_token` | `backend_error_text` | `Länken är ogiltig eller har gått ut.` | `P_AUTH` |
| `auth.error.invalid_current_password` | `backend_error_text` | `Det nuvarande lösenordet stämmer inte.` | `P_AUTH` |
| `auth.error.new_password_must_differ` | `backend_error_text` | `Välj ett nytt lösenord som skiljer sig från det nuvarande.` | `P_AUTH` |
| `auth.error.invalid_credentials` | `backend_error_text` | `E-post eller lösenord stämmer inte.` | `P_AUTH` |
| `auth.error.unauthenticated` | `backend_error_text` | `Logga in för att fortsätta.` | `P_AUTH` |
| `auth.error.refresh_token_invalid` | `backend_error_text` | `Din inloggning behöver förnyas. Logga in igen.` | `P_AUTH` |
| `auth.error.email_already_registered` | `backend_error_text` | `Det finns redan ett konto med den e-postadressen.` | `P_AUTH` |
| `auth.error.validation_error` | `backend_error_text` | `Kontrollera uppgifterna och försök igen.` | `P_AUTH` |
| `auth.error.rate_limited` | `backend_error_text` | `För många försök. Vänta en stund och försök igen.` | `P_AUTH` |
| `auth.error.internal_error` | `backend_error_text` | `Något gick fel. Försök igen om en stund.` | `P_AUTH` |

### Onboarding

| text_id | authority_class | value_sv | provenance |
|---|---|---|---|
| `onboarding.create_profile.title` | `contract_text` | `Skapa din profil` | `P_ONBOARDING` |
| `onboarding.create_profile.body` | `contract_text` | `Berätta vad du vill heta i Aveli. Du kan lägga till en kort presentation nu eller senare.` | `P_ONBOARDING` |
| `onboarding.create_profile.display_name_label` | `contract_text` | `Visningsnamn` | `P_ONBOARDING` |
| `onboarding.create_profile.bio_label` | `contract_text` | `Presentation` | `P_ONBOARDING` |
| `onboarding.create_profile.submit_action` | `contract_text` | `Fortsätt` | `P_ONBOARDING` |
| `onboarding.create_profile.saving_status` | `backend_status_text` | `Sparar din profil...` | `P_ONBOARDING` |
| `onboarding.create_profile.success_status` | `backend_status_text` | `Profilen är sparad.` | `P_ONBOARDING` |
| `onboarding.create_profile.display_name_required_error` | `backend_error_text` | `Ange ett visningsnamn för att fortsätta.` | `P_ONBOARDING` |
| `onboarding.welcome.title` | `contract_text` | `Välkommen till Aveli` | `P_ONBOARDING` |
| `onboarding.welcome.body` | `contract_text` | `Här börjar din plats för lärande, gemenskap och fördjupning.` | `P_ONBOARDING` |
| `onboarding.welcome.confirmation_action` | `contract_text` | `Jag förstår hur Aveli fungerar` | `P_ONBOARDING` |
| `onboarding.welcome.completing_status` | `backend_status_text` | `Slutför välkomststeget...` | `P_ONBOARDING` |
| `onboarding.welcome.completed_status` | `backend_status_text` | `Välkomststeget är klart.` | `P_ONBOARDING` |
| `onboarding.error.welcome_confirmation_required` | `backend_error_text` | `Bekräfta välkomststeget för att fortsätta.` | `P_ONBOARDING` |
| `onboarding.error.subject_not_found` | `backend_error_text` | `Kontot kunde inte hittas. Logga in igen.` | `P_ONBOARDING` |
| `onboarding.error.profile_not_found` | `backend_error_text` | `Profilen kunde inte hittas.` | `P_ONBOARDING` |
| `onboarding.error.already_teacher` | `backend_error_text` | `Användaren är redan lärare.` | `P_ONBOARDING` |
| `onboarding.error.already_learner` | `backend_error_text` | `Användaren är redan lärande medlem.` | `P_ONBOARDING` |
| `onboarding.error.admin_bootstrap_already_consumed` | `backend_error_text` | `Den första administratören är redan skapad.` | `P_ONBOARDING` |
| `onboarding.error.forbidden` | `backend_error_text` | `Du har inte behörighet att göra det här.` | `P_ONBOARDING` |
| `onboarding.error.admin_required` | `backend_error_text` | `Administratörsbehörighet krävs.` | `P_ONBOARDING` |

### Email

| text_id | authority_class | value_sv | provenance |
|---|---|---|---|
| `email.verify.subject` | `backend_email_text` | `Bekräfta din e-postadress` | `P_EMAIL` |
| `email.verify.heading` | `backend_email_text` | `Bekräfta din e-postadress` | `P_EMAIL` |
| `email.verify.body_intro` | `backend_email_text` | `Välkommen till Aveli.` | `P_EMAIL` |
| `email.verify.body_instruction` | `backend_email_text` | `Bekräfta din e-postadress för att fortsätta.` | `P_EMAIL` |
| `email.verify.cta` | `backend_email_text` | `Bekräfta e-postadress` | `P_EMAIL` |
| `email.verify.plain_text` | `backend_email_text` | `Bekräfta din e-postadress för att fortsätta i Aveli.` | `P_EMAIL` |
| `email.verify.footer` | `backend_email_text` | `Om du inte bad om detta kan du ignorera mejlet.` | `P_EMAIL` |
| `email.password_reset.subject` | `backend_email_text` | `Återställ ditt lösenord` | `P_EMAIL` |
| `email.password_reset.heading` | `backend_email_text` | `Återställ ditt lösenord` | `P_EMAIL` |
| `email.password_reset.body_intro` | `backend_email_text` | `Vi har tagit emot en begäran om att återställa ditt lösenord.` | `P_EMAIL` |
| `email.password_reset.body_instruction` | `backend_email_text` | `Välj ett nytt lösenord för att fortsätta använda Aveli.` | `P_EMAIL` |
| `email.password_reset.cta` | `backend_email_text` | `Välj nytt lösenord` | `P_EMAIL` |
| `email.password_reset.plain_text` | `backend_email_text` | `Välj ett nytt lösenord för ditt Aveli-konto.` | `P_EMAIL` |
| `email.password_reset.footer` | `backend_email_text` | `Om du inte bad om detta kan du ignorera mejlet.` | `P_EMAIL` |
| `email.referral.subject` | `backend_email_text` | `Du är inbjuden till Aveli` | `P_EMAIL` |
| `email.referral.heading` | `backend_email_text` | `Du är inbjuden till Aveli` | `P_EMAIL` |
| `email.referral.body_intro` | `backend_email_text` | `En lärare har bjudit in dig till Aveli.` | `P_EMAIL` |
| `email.referral.body_invitation` | `backend_email_text` | `Skapa ditt konto för att ta del av din inbjudan.` | `P_EMAIL` |
| `email.referral.cta` | `backend_email_text` | `Ta emot inbjudan` | `P_EMAIL` |
| `email.referral.plain_text` | `backend_email_text` | `Skapa ditt konto i Aveli för att ta emot inbjudan.` | `P_EMAIL` |
| `email.referral.footer` | `backend_email_text` | `Om du inte känner igen inbjudan kan du ignorera mejlet.` | `P_EMAIL` |
| `email.referral.error.invalid_referral` | `backend_error_text` | `Inbjudan är ogiltig eller har gått ut.` | `P_EMAIL` |
| `email.referral.error.already_redeemed` | `backend_error_text` | `Inbjudan har redan använts.` | `P_EMAIL` |
| `email.referral.error.send_failed` | `backend_error_text` | `Inbjudan kunde inte skickas. Försök igen.` | `P_EMAIL` |
| `email.referral.status.sent` | `backend_status_text` | `Inbjudan är skickad.` | `P_EMAIL` |
| `email.verify.error.invalid_token` | `backend_error_text` | `Bekräftelselänken är ogiltig.` | `P_EMAIL` |
| `email.verify.error.expired_token` | `backend_error_text` | `Bekräftelselänken har gått ut.` | `P_EMAIL` |
| `email.verify.error.send_failed` | `backend_error_text` | `Bekräftelselänken kunde inte skickas. Försök igen.` | `P_EMAIL` |

### Profile

| text_id | authority_class | value_sv | provenance |
|---|---|---|---|
| `profile.page.title` | `contract_text` | `Din profil` | `P_PROFILE` |
| `profile.form.display_name_label` | `contract_text` | `Visningsnamn` | `P_PROFILE` |
| `profile.form.bio_label` | `contract_text` | `Presentation` | `P_PROFILE` |
| `profile.form.save_action` | `contract_text` | `Spara profil` | `P_PROFILE` |
| `profile.form.saving_status` | `backend_status_text` | `Sparar profilen...` | `P_PROFILE` |
| `profile.form.saved_status` | `backend_status_text` | `Profilen är sparad.` | `P_PROFILE` |
| `profile.form.save_failed_error` | `backend_error_text` | `Profilen kunde inte sparas. Försök igen.` | `P_PROFILE` |
| `profile.password.change_action` | `contract_text` | `Byt lösenord` | `P_PROFILE` |
| `profile.password.change_title` | `contract_text` | `Byt lösenord` | `P_PROFILE` |
| `profile.password.reset_send_action` | `contract_text` | `Skicka återställningslänk` | `P_PROFILE` |
| `profile.password.reset_sent_status` | `backend_status_text` | `En återställningslänk är skickad.` | `P_PROFILE` |
| `profile.password.reset_failed_error` | `backend_error_text` | `Återställningslänken kunde inte skickas. Försök igen.` | `P_PROFILE` |
| `profile.error.profile_not_found` | `backend_error_text` | `Profilen kunde inte hittas.` | `P_PROFILE` |
| `profile.error.update_failed` | `backend_error_text` | `Profilen kunde inte uppdateras. Försök igen.` | `P_PROFILE` |
| `profile.error.unauthenticated` | `backend_error_text` | `Logga in för att se din profil.` | `P_PROFILE` |
| `profile.public.title` | `contract_text` | `Profil` | `P_PROFILE` |
| `profile.public.display_name_label` | `contract_text` | `Namn` | `P_PROFILE` |
| `profile.public.bio_label` | `contract_text` | `Presentation` | `P_PROFILE` |
| `profile.public.courses_label` | `contract_text` | `Kurser` | `P_PROFILE` |
| `profile.public.services_label` | `contract_text` | `Tjänster` | `P_PROFILE` |
| `profile.public.empty_bio_status` | `backend_status_text` | `Ingen presentation är tillagd ännu.` | `P_PROFILE` |
| `profile.logout.title` | `contract_text` | `Logga ut` | `P_PROFILE` |
| `profile.logout.body` | `contract_text` | `Du kan logga in igen när du vill fortsätta.` | `P_PROFILE` |
| `profile.logout.action` | `contract_text` | `Logga ut` | `P_PROFILE` |
| `profile.logout.loading_status` | `backend_status_text` | `Loggar ut...` | `P_PROFILE` |
| `profile.logout.completed_status` | `backend_status_text` | `Du är utloggad.` | `P_PROFILE` |
| `profile.teacher_card.teacher_label` | `contract_text` | `Lärare` | `P_PROFILE` |
| `profile.teacher_card.open_profile_action` | `contract_text` | `Visa profil` | `P_PROFILE` |
| `profile.teacher_card.no_bio_status` | `backend_status_text` | `Ingen presentation är tillagd ännu.` | `P_PROFILE` |

### Checkout And Payments

| text_id | authority_class | value_sv | provenance |
|---|---|---|---|
| `checkout.membership.headline` | `backend_stripe_text` | `Starta ditt medlemskap i Aveli` | `P_CHECKOUT` |
| `checkout.membership.trial_card_line` | `backend_stripe_text` | `Du får 14 dagar att testa appen. Kortuppgifter krävs, men du debiteras inte under provperioden.` | `P_CHECKOUT` |
| `checkout.membership.contents_live_lessons` | `backend_stripe_text` | `Direktsända lektioner` | `P_CHECKOUT` |
| `checkout.membership.contents_course_access` | `backend_stripe_text` | `Tillgång till ett stort kursutbud och en plattform för likasinnade spirituellt intresserade människor i olika skeden av sin utveckling` | `P_CHECKOUT` |
| `checkout.membership.contents_meditations` | `backend_stripe_text` | `Meditationsmusik och guidade meditationer` | `P_CHECKOUT` |
| `checkout.membership.contents_safe_learning` | `backend_stripe_text` | `En trygg plats för lärande och spirituell utveckling` | `P_CHECKOUT` |
| `checkout.membership.trust_line` | `backend_stripe_text` | `Betalningen hanteras säkert av Stripe. Aveli uppdaterar din åtkomst först när betalningen har bekräftats av servern.` | `P_CHECKOUT` |
| `checkout.membership.primary_action` | `backend_stripe_text` | `Fortsätt till betalning` | `P_CHECKOUT` |
| `checkout.membership.creating_status` | `backend_status_text` | `Förbereder din säkra betalning...` | `P_CHECKOUT` |
| `checkout.membership.creation_failed_error` | `backend_error_text` | `Betalningen kunde inte startas. Försök igen.` | `P_CHECKOUT` |
| `checkout.embedded.loading` | `backend_status_text` | `Förbereder betalningen...` | `P_CHECKOUT` |
| `checkout.embedded.unsupported` | `backend_status_text` | `Betalning stöds inte i den här vyn.` | `P_CHECKOUT` |
| `checkout.embedded.retry_action` | `contract_text` | `Försök igen` | `P_CHECKOUT` |
| `checkout.embedded.close_action` | `contract_text` | `Stäng` | `P_CHECKOUT` |
| `checkout.return.title` | `backend_stripe_text` | `Betalning` | `P_CHECKOUT` |
| `checkout.return.waiting_status` | `backend_status_text` | `Vi bekräftar ditt medlemskap. Det kan ta en kort stund innan betalningen är klar hos Stripe.` | `P_CHECKOUT` |
| `checkout.return.retry_action` | `contract_text` | `Kontrollera igen` | `P_CHECKOUT` |
| `checkout.return.confirmed_status` | `backend_status_text` | `Ditt medlemskap är bekräftat. Nu fortsätter du med att skapa din profil.` | `P_CHECKOUT` |
| `checkout.return.failed_status` | `backend_error_text` | `Betalningen kunde inte bekräftas. Försök igen.` | `P_CHECKOUT` |
| `checkout.cancel.title` | `backend_stripe_text` | `Betalningen avbröts` | `P_CHECKOUT` |
| `checkout.cancel.body` | `backend_stripe_text` | `Betalningen avbröts. Din åtkomst ändras inte.` | `P_CHECKOUT` |
| `checkout.cancel.retry_action` | `contract_text` | `Försök igen` | `P_CHECKOUT` |
| `checkout.paywall.title` | `contract_text` | `Medlemskap krävs` | `P_CHECKOUT` |
| `checkout.paywall.body` | `contract_text` | `Starta ditt medlemskap för att fortsätta.` | `P_CHECKOUT` |
| `checkout.paywall.primary_action` | `contract_text` | `Starta medlemskap` | `P_CHECKOUT` |
| `checkout.paywall.dismiss_action` | `contract_text` | `Inte nu` | `P_CHECKOUT` |
| `checkout.booking.title` | `contract_text` | `Bokning` | `P_CHECKOUT` |
| `checkout.booking.unavailable_status` | `backend_status_text` | `Bokning är inte tillgänglig just nu.` | `P_CHECKOUT` |
| `checkout.booking.contact_action` | `contract_text` | `Kontakta läraren` | `P_CHECKOUT` |
| `checkout.course.title` | `backend_stripe_text` | `Köp kurs` | `P_CHECKOUT` |
| `checkout.course.start_action` | `backend_stripe_text` | `Fortsätt till betalning` | `P_CHECKOUT` |
| `checkout.course.loading_status` | `backend_status_text` | `Förbereder betalningen...` | `P_CHECKOUT` |
| `checkout.course.failed_error` | `backend_error_text` | `Kursköpet kunde inte startas. Försök igen.` | `P_CHECKOUT` |
| `checkout.course.unavailable_error` | `backend_error_text` | `Kursköp är inte tillgängligt just nu.` | `P_CHECKOUT` |
| `checkout.bundle.title` | `backend_stripe_text` | `Köp kurspaket` | `P_CHECKOUT` |
| `checkout.bundle.start_action` | `backend_stripe_text` | `Fortsätt till betalning` | `P_CHECKOUT` |
| `checkout.bundle.loading_status` | `backend_status_text` | `Förbereder betalningen...` | `P_CHECKOUT` |
| `checkout.bundle.failed_error` | `backend_error_text` | `Kurspaketet kunde inte köpas. Försök igen.` | `P_CHECKOUT` |
| `checkout.bundle.unavailable_error` | `backend_error_text` | `Kurspaketet är inte tillgängligt just nu.` | `P_CHECKOUT` |
| `checkout.error.checkout_unavailable` | `backend_error_text` | `Betalning är inte tillgänglig just nu.` | `P_CHECKOUT` |
| `checkout.error.session_create_failed` | `backend_error_text` | `Betalningen kunde inte startas. Försök igen.` | `P_CHECKOUT` |
| `checkout.error.customer_create_failed` | `backend_error_text` | `Betalningen kunde inte förberedas. Försök igen.` | `P_CHECKOUT` |
| `checkout.error.subscription_create_failed` | `backend_error_text` | `Medlemskapet kunde inte skapas. Försök igen.` | `P_CHECKOUT` |
| `checkout.error.payment_required` | `backend_error_text` | `Betalning krävs för att fortsätta.` | `P_CHECKOUT` |
| `checkout.error.membership_not_confirmed` | `backend_error_text` | `Medlemskapet är inte bekräftat ännu.` | `P_CHECKOUT` |
| `payments.status.waiting` | `backend_status_text` | `Vi bekräftar betalningen. Det kan ta en kort stund.` | `P_CHECKOUT` |
| `payments.status.confirmed` | `backend_status_text` | `Betalningen är bekräftad.` | `P_CHECKOUT` |
| `payments.status.failed` | `backend_error_text` | `Betalningen kunde inte genomföras.` | `P_CHECKOUT` |
| `payments.status.canceled` | `backend_status_text` | `Betalningen avbröts.` | `P_CHECKOUT` |
| `payments.status.retrying` | `backend_status_text` | `Kontrollerar betalningen igen...` | `P_CHECKOUT` |
| `payments.action.retry` | `contract_text` | `Försök igen` | `P_CHECKOUT` |
| `payments.error.provider_unavailable` | `backend_error_text` | `Betalningen är inte tillgänglig just nu.` | `P_CHECKOUT` |
| `payments.error.payment_not_confirmed` | `backend_error_text` | `Betalningen är inte bekräftad ännu.` | `P_CHECKOUT` |
| `payments.error.checkout_session_failed` | `backend_error_text` | `Betalningen kunde inte slutföras. Försök igen.` | `P_CHECKOUT` |

### Home And Community

| text_id | authority_class | value_sv | provenance |
|---|---|---|---|
| `home.dashboard.title` | `contract_text` | `Hem` | `P_HOME_COMMUNITY` |
| `home.dashboard.welcome_heading` | `contract_text` | `Välkommen tillbaka` | `P_HOME_COMMUNITY` |
| `home.dashboard.feed_heading` | `contract_text` | `Aktuellt` | `P_HOME_COMMUNITY` |
| `home.dashboard.services_heading` | `contract_text` | `Tjänster` | `P_HOME_COMMUNITY` |
| `home.dashboard.empty_feed_status` | `backend_status_text` | `Det finns inget nytt att visa ännu.` | `P_HOME_COMMUNITY` |
| `home.dashboard.empty_services_status` | `backend_status_text` | `Inga tjänster är tillgängliga just nu.` | `P_HOME_COMMUNITY` |
| `home.dashboard.loading_status` | `backend_status_text` | `Läser in hemvyn...` | `P_HOME_COMMUNITY` |
| `home.dashboard.load_failed_error` | `backend_error_text` | `Hemvyn kunde inte läsas in. Försök igen.` | `P_HOME_COMMUNITY` |
| `home.feed.title` | `contract_text` | `Aktuellt` | `P_HOME_COMMUNITY` |
| `home.feed.empty_status` | `backend_status_text` | `Det finns inga inlägg att visa ännu.` | `P_HOME_COMMUNITY` |
| `home.feed.loading_status` | `backend_status_text` | `Läser in aktuellt innehåll...` | `P_HOME_COMMUNITY` |
| `home.feed.load_failed_error` | `backend_error_text` | `Innehållet kunde inte läsas in.` | `P_HOME_COMMUNITY` |
| `home.feed.retry_action` | `contract_text` | `Försök igen` | `P_HOME_COMMUNITY` |
| `home.certification.title` | `backend_status_text` | `Certifiering` | `P_HOME_COMMUNITY` |
| `home.certification.login_required_status` | `backend_status_text` | `Logga in för att se certifiering.` | `P_HOME_COMMUNITY` |
| `home.certification.unavailable_status` | `backend_status_text` | `Certifiering är inte tillgänglig just nu.` | `P_HOME_COMMUNITY` |
| `home.certification.retry_action` | `contract_text` | `Försök igen` | `P_HOME_COMMUNITY` |
| `community.home.title` | `contract_text` | `Gemenskap` | `P_HOME_COMMUNITY` |
| `community.home.teachers_heading` | `contract_text` | `Lärare` | `P_HOME_COMMUNITY` |
| `community.home.services_heading` | `contract_text` | `Tjänster` | `P_HOME_COMMUNITY` |
| `community.navigation.home_label` | `contract_text` | `Hem` | `P_HOME_COMMUNITY` |
| `community.navigation.teachers_label` | `contract_text` | `Lärare` | `P_HOME_COMMUNITY` |
| `community.navigation.services_label` | `contract_text` | `Tjänster` | `P_HOME_COMMUNITY` |
| `community.error.load_failed` | `backend_error_text` | `Gemenskapen kunde inte läsas in. Försök igen.` | `P_HOME_COMMUNITY` |
| `community.teacher.title` | `contract_text` | `Lärare` | `P_HOME_COMMUNITY` |
| `community.teacher.services_heading` | `contract_text` | `Tjänster` | `P_HOME_COMMUNITY` |
| `community.teacher.empty_services_status` | `backend_status_text` | `Läraren har inga tjänster publicerade ännu.` | `P_HOME_COMMUNITY` |
| `community.service.title` | `contract_text` | `Tjänst` | `P_HOME_COMMUNITY` |
| `community.service.booking_action` | `contract_text` | `Boka` | `P_HOME_COMMUNITY` |
| `community.service.booking_unavailable_status` | `backend_status_text` | `Bokning är inte tillgänglig just nu.` | `P_HOME_COMMUNITY` |
| `community.service.load_failed_error` | `backend_error_text` | `Tjänsten kunde inte läsas in.` | `P_HOME_COMMUNITY` |
| `community.tarot.title` | `contract_text` | `Tarot` | `P_HOME_COMMUNITY` |
| `community.tarot.body` | `contract_text` | `Utforska vägledning genom tarot.` | `P_HOME_COMMUNITY` |
| `community.tarot.start_action` | `contract_text` | `Starta` | `P_HOME_COMMUNITY` |
| `community.tarot.loading_status` | `backend_status_text` | `Förbereder tarot...` | `P_HOME_COMMUNITY` |
| `community.tarot.unavailable_status` | `backend_status_text` | `Tarot är inte tillgängligt just nu.` | `P_HOME_COMMUNITY` |
| `community.tarot.error` | `backend_error_text` | `Tarot kunde inte startas. Försök igen.` | `P_HOME_COMMUNITY` |
| `community.error.profile_not_found` | `backend_error_text` | `Profilen kunde inte hittas.` | `P_HOME_COMMUNITY` |
| `community.error.service_not_found` | `backend_error_text` | `Tjänsten kunde inte hittas.` | `P_HOME_COMMUNITY` |
| `community.error.unauthenticated` | `backend_error_text` | `Logga in för att fortsätta.` | `P_HOME_COMMUNITY` |
| `community.error.forbidden` | `backend_error_text` | `Du har inte behörighet att se detta.` | `P_HOME_COMMUNITY` |
| `community.error.internal_error` | `backend_error_text` | `Något gick fel. Försök igen.` | `P_HOME_COMMUNITY` |
| `community.service.error.not_found` | `backend_error_text` | `Tjänsten kunde inte hittas.` | `P_HOME_COMMUNITY` |
| `community.service.error.load_failed` | `backend_error_text` | `Tjänsten kunde inte läsas in.` | `P_HOME_COMMUNITY` |
| `home.feed.error.load_failed` | `backend_error_text` | `Aktuellt innehåll kunde inte läsas in.` | `P_HOME_COMMUNITY` |
| `home.feed.error.internal_error` | `backend_error_text` | `Något gick fel när innehållet skulle hämtas.` | `P_HOME_COMMUNITY` |

### Course And Lesson

| text_id | authority_class | value_sv | provenance |
|---|---|---|---|
| `course_lesson.catalog.title` | `contract_text` | `Kurser` | `P_COURSE` |
| `course_lesson.catalog.empty_status` | `backend_status_text` | `Det finns inga kurser att visa ännu.` | `P_COURSE` |
| `course_lesson.catalog.loading_status` | `backend_status_text` | `Läser in kurser...` | `P_COURSE` |
| `course_lesson.catalog.load_failed_error` | `backend_error_text` | `Kurserna kunde inte läsas in.` | `P_COURSE` |
| `course_lesson.catalog.retry_action` | `contract_text` | `Försök igen` | `P_COURSE` |
| `course_lesson.intro.title` | `contract_text` | `Introduktion` | `P_COURSE` |
| `course_lesson.intro.start_action` | `contract_text` | `Starta introduktion` | `P_COURSE` |
| `course_lesson.intro.continue_action` | `contract_text` | `Fortsätt` | `P_COURSE` |
| `course_lesson.intro.unavailable_status` | `backend_status_text` | `Introduktionen är inte tillgänglig just nu.` | `P_COURSE` |
| `course_lesson.detail.lessons_heading` | `contract_text` | `Lektioner` | `P_COURSE` |
| `course_lesson.detail.price_label` | `contract_text` | `Pris` | `P_COURSE` |
| `course_lesson.detail.access_included_status` | `backend_status_text` | `Ingår i din åtkomst.` | `P_COURSE` |
| `course_lesson.detail.purchase_action` | `contract_text` | `Köp kurs` | `P_COURSE` |
| `course_lesson.detail.loading_status` | `backend_status_text` | `Läser in kursen...` | `P_COURSE` |
| `course_lesson.detail.load_failed_error` | `backend_error_text` | `Kursen kunde inte läsas in.` | `P_COURSE` |
| `course_lesson.redirect.loading_status` | `backend_status_text` | `Förbereder kursen...` | `P_COURSE` |
| `course_lesson.redirect.success_status` | `backend_status_text` | `Kursen är redo.` | `P_COURSE` |
| `course_lesson.redirect.failed_error` | `backend_error_text` | `Kursen kunde inte öppnas. Försök igen.` | `P_COURSE` |
| `course_lesson.access_gate.locked_title` | `backend_status_text` | `Lektion låst` | `P_COURSE` |
| `course_lesson.access_gate.locked_body` | `backend_status_text` | `Du behöver åtkomst till kursen för att se den här lektionen.` | `P_COURSE` |
| `course_lesson.access_gate.login_required_status` | `backend_status_text` | `Logga in för att fortsätta.` | `P_COURSE` |
| `course_lesson.access_gate.purchase_required_status` | `backend_status_text` | `Köp kursen för att fortsätta.` | `P_COURSE` |
| `course_lesson.access_gate.forbidden_error` | `backend_error_text` | `Du har inte behörighet att se den här lektionen.` | `P_COURSE` |
| `course_lesson.lesson.title_label` | `contract_text` | `Lektion` | `P_COURSE` |
| `course_lesson.lesson.content_loading_status` | `backend_status_text` | `Läser in lektionen...` | `P_COURSE` |
| `course_lesson.lesson.content_empty_status` | `backend_status_text` | `Lektionsinnehållet är inte tillagt ännu.` | `P_COURSE` |
| `course_lesson.lesson.media_loading_status` | `backend_status_text` | `Läser in media...` | `P_COURSE` |
| `course_lesson.lesson.media_unavailable_status` | `backend_status_text` | `Media är inte tillgänglig just nu.` | `P_COURSE` |
| `course_lesson.lesson.load_failed_error` | `backend_error_text` | `Lektionen kunde inte läsas in.` | `P_COURSE` |
| `course_lesson.lesson.retry_action` | `contract_text` | `Försök igen` | `P_COURSE` |
| `course_lesson.error.course_not_found` | `backend_error_text` | `Kursen kunde inte hittas.` | `P_COURSE` |
| `course_lesson.error.lesson_not_found` | `backend_error_text` | `Lektionen kunde inte hittas.` | `P_COURSE` |
| `course_lesson.error.enrollment_required` | `backend_error_text` | `Du behöver åtkomst till kursen för att fortsätta.` | `P_COURSE` |
| `course_lesson.error.lesson_locked` | `backend_error_text` | `Den här lektionen är låst just nu.` | `P_COURSE` |
| `course_lesson.error.internal_error` | `backend_error_text` | `Något gick fel när kursen skulle hämtas.` | `P_COURSE` |
| `course_lesson.card.open_course_action` | `contract_text` | `Öppna kurs` | `P_COURSE` |
| `course_lesson.card.price_label` | `contract_text` | `Pris` | `P_COURSE` |
| `course_lesson.card.included_status` | `backend_status_text` | `Ingår i din åtkomst.` | `P_COURSE` |
| `course_lesson.card.teacher_label` | `contract_text` | `Lärare` | `P_COURSE` |

### Studio, Editor, And Home Player

| text_id | authority_class | value_sv | provenance |
|---|---|---|---|
| `studio_editor.entry.title` | `contract_text` | `Studio` | `P_STUDIO` |
| `studio_editor.entry.teacher_required_status` | `backend_status_text` | `Lärarbehörighet krävs för att öppna Studio.` | `P_STUDIO` |
| `studio_editor.entry.loading_status` | `backend_status_text` | `Öppnar Studio...` | `P_STUDIO` |
| `studio_editor.entry.load_failed_error` | `backend_error_text` | `Studio kunde inte öppnas. Försök igen.` | `P_STUDIO` |
| `studio_editor.entry.open_dashboard_action` | `contract_text` | `Öppna Studio` | `P_STUDIO` |
| `studio_editor.teacher_home.title` | `contract_text` | `Lärarstudio` | `P_STUDIO` |
| `studio_editor.teacher_home.courses_heading` | `contract_text` | `Dina kurser` | `P_STUDIO` |
| `studio_editor.teacher_home.home_player_heading` | `contract_text` | `Hemspelare` | `P_STUDIO` |
| `studio_editor.teacher_home.create_course_action` | `contract_text` | `Skapa kurs` | `P_STUDIO` |
| `studio_editor.teacher_home.empty_courses_status` | `backend_status_text` | `Du har inga kurser ännu.` | `P_STUDIO` |
| `studio_editor.teacher_home.load_failed_error` | `backend_error_text` | `Lärarstudion kunde inte läsas in.` | `P_STUDIO` |
| `studio_editor.course_editor.title` | `contract_text` | `Kursredigerare` | `P_STUDIO` |
| `studio_editor.course_editor.course_title_label` | `contract_text` | `Kurstitel` | `P_STUDIO` |
| `studio_editor.course_editor.slug_label` | `contract_text` | `Webbadressnamn` | `P_STUDIO` |
| `studio_editor.course_editor.price_label` | `contract_text` | `Pris` | `P_STUDIO` |
| `studio_editor.course_editor.save_action` | `contract_text` | `Spara kurs` | `P_STUDIO` |
| `studio_editor.course_editor.saving_status` | `backend_status_text` | `Sparar kursen...` | `P_STUDIO` |
| `studio_editor.course_editor.saved_status` | `backend_status_text` | `Kursen är sparad.` | `P_STUDIO` |
| `studio_editor.course_editor.save_failed_error` | `backend_error_text` | `Kursen kunde inte sparas. Försök igen.` | `P_STUDIO` |
| `studio_editor.course_editor.preview_action` | `contract_text` | `Förhandsvisa` | `P_STUDIO` |
| `studio_editor.validation.course_title_required` | `backend_error_text` | `Ange en kurstitel.` | `P_STUDIO` |
| `studio_editor.validation.slug_required` | `backend_error_text` | `Ange ett webbadressnamn.` | `P_STUDIO` |
| `studio_editor.validation.lesson_title_required` | `backend_error_text` | `Ange en lektionstitel.` | `P_STUDIO` |
| `studio_editor.validation.position_required` | `backend_error_text` | `Ange lektionsordning.` | `P_STUDIO` |
| `studio_editor.validation.content_required` | `backend_error_text` | `Lägg till lektionsinnehåll.` | `P_STUDIO` |
| `studio_editor.media_controls.title` | `contract_text` | `Media` | `P_STUDIO` |
| `studio_editor.media_controls.add_media_action` | `contract_text` | `Lägg till media` | `P_STUDIO` |
| `studio_editor.media_controls.remove_media_action` | `contract_text` | `Ta bort media` | `P_STUDIO` |
| `studio_editor.media_controls.processing_status` | `backend_status_text` | `Media bearbetas...` | `P_STUDIO` |
| `studio_editor.media_controls.ready_status` | `backend_status_text` | `Media är redo.` | `P_STUDIO` |
| `studio_editor.media_controls.failed_error` | `backend_error_text` | `Media kunde inte bearbetas.` | `P_STUDIO` |
| `studio_editor.lesson_media_preview.loading_status` | `backend_status_text` | `Läser in media...` | `P_STUDIO` |
| `studio_editor.lesson_media_preview.empty_status` | `backend_status_text` | `Ingen media är tillagd ännu.` | `P_STUDIO` |
| `studio_editor.lesson_media_preview.unavailable_status` | `backend_status_text` | `Media är inte tillgänglig just nu.` | `P_STUDIO` |
| `studio_editor.lesson_media_preview.failed_error` | `backend_error_text` | `Media kunde inte visas.` | `P_STUDIO` |
| `studio_editor.profile_media.title` | `contract_text` | `Profilmedia` | `P_STUDIO` |
| `studio_editor.profile_media.upload_action` | `contract_text` | `Ladda upp bild` | `P_STUDIO` |
| `studio_editor.profile_media.replace_action` | `contract_text` | `Byt bild` | `P_STUDIO` |
| `studio_editor.profile_media.processing_status` | `backend_status_text` | `Bilden bearbetas...` | `P_STUDIO` |
| `studio_editor.profile_media.ready_status` | `backend_status_text` | `Bilden är redo.` | `P_STUDIO` |
| `studio_editor.profile_media.failed_error` | `backend_error_text` | `Bilden kunde inte bearbetas.` | `P_STUDIO` |
| `studio_editor.cover_upload.title` | `contract_text` | `Omslagsbild` | `P_STUDIO` |
| `studio_editor.cover_upload.choose_action` | `contract_text` | `Välj bild` | `P_STUDIO` |
| `studio_editor.cover_upload.change_action` | `contract_text` | `Byt bild` | `P_STUDIO` |
| `studio_editor.cover_upload.remove_action` | `contract_text` | `Ta bort bild` | `P_STUDIO` |
| `studio_editor.cover_upload.uploading_status` | `backend_status_text` | `Laddar upp bild...` | `P_STUDIO` |
| `studio_editor.cover_upload.failed_error` | `backend_error_text` | `Omslagsbilden kunde inte laddas upp.` | `P_STUDIO` |
| `studio_editor.audio_upload.title` | `contract_text` | `Ljudfil` | `P_STUDIO` |
| `studio_editor.audio_upload.choose_action` | `contract_text` | `Välj ljudfil` | `P_STUDIO` |
| `studio_editor.audio_upload.uploading_status` | `backend_status_text` | `Laddar upp ljudfil...` | `P_STUDIO` |
| `studio_editor.audio_upload.processing_status` | `backend_status_text` | `Ljudfilen bearbetas...` | `P_STUDIO` |
| `studio_editor.audio_upload.failed_error` | `backend_error_text` | `Ljudfilen kunde inte laddas upp.` | `P_STUDIO` |
| `studio_editor.audio_replace.title` | `contract_text` | `Byt ljudfil` | `P_STUDIO` |
| `studio_editor.audio_replace.confirm_action` | `contract_text` | `Byt ljudfil` | `P_STUDIO` |
| `studio_editor.audio_replace.cancel_action` | `contract_text` | `Avbryt` | `P_STUDIO` |
| `home.player_upload.title` | `contract_text` | `Lägg till ljud i hemspelaren` | `P_STUDIO` |
| `home.player_upload.audio_label` | `contract_text` | `Ljudfil` | `P_STUDIO` |
| `home.player_upload.submit_action` | `contract_text` | `Ladda upp` | `P_STUDIO` |
| `home.player_upload.uploading_status` | `backend_status_text` | `Laddar upp ljud...` | `P_STUDIO` |
| `home.player_upload.processing_status` | `backend_status_text` | `Ljudet bearbetas...` | `P_STUDIO` |
| `home.player_upload.ready_status` | `backend_status_text` | `Ljudet är redo.` | `P_STUDIO` |
| `home.player_upload.failed_error` | `backend_error_text` | `Ljudet kunde inte laddas upp.` | `P_STUDIO` |
| `studio_editor.error.course_not_found` | `backend_error_text` | `Kursen kunde inte hittas.` | `P_STUDIO` |
| `studio_editor.error.lesson_not_found` | `backend_error_text` | `Lektionen kunde inte hittas.` | `P_STUDIO` |
| `studio_editor.error.teacher_required` | `backend_error_text` | `Lärarbehörighet krävs.` | `P_STUDIO` |
| `studio_editor.error.owner_required` | `backend_error_text` | `Du behöver vara ansvarig lärare för den här kursen.` | `P_STUDIO` |
| `studio_editor.error.save_conflict` | `backend_error_text` | `Innehållet har ändrats sedan du öppnade det. Läs in igen och försök på nytt.` | `P_STUDIO` |
| `studio_editor.status.reloading` | `backend_status_text` | `Läser in igen...` | `P_STUDIO` |

### Admin And Media System

| text_id | authority_class | value_sv | provenance |
|---|---|---|---|
| `admin.teacher_role.title` | `contract_text` | `Lärarbehörighet` | `P_ADMIN` |
| `admin.teacher_role.user_id_label` | `contract_text` | `Användare` | `P_ADMIN` |
| `admin.teacher_role.grant_action` | `contract_text` | `Ge lärarbehörighet` | `P_ADMIN` |
| `admin.teacher_role.revoke_action` | `contract_text` | `Ta bort lärarbehörighet` | `P_ADMIN` |
| `admin.teacher_role.granting_status` | `backend_status_text` | `Ger lärarbehörighet...` | `P_ADMIN` |
| `admin.teacher_role.revoking_status` | `backend_status_text` | `Tar bort lärarbehörighet...` | `P_ADMIN` |
| `admin.teacher_role.granted_status` | `backend_status_text` | `Lärarbehörigheten är tillagd.` | `P_ADMIN` |
| `admin.teacher_role.revoked_status` | `backend_status_text` | `Lärarbehörigheten är borttagen.` | `P_ADMIN` |
| `admin.teacher_role.failed_error` | `backend_error_text` | `Lärarbehörigheten kunde inte uppdateras.` | `P_ADMIN` |
| `admin.settings.title` | `contract_text` | `Admininställningar` | `P_ADMIN` |
| `admin.settings.bootstrap_heading` | `contract_text` | `Första administratören` | `P_ADMIN` |
| `admin.settings.bootstrap_status` | `backend_status_text` | `Administratörsstatus är klar.` | `P_ADMIN` |
| `admin.settings.reload_action` | `contract_text` | `Läs in igen` | `P_ADMIN` |
| `admin.settings.saved_status` | `backend_status_text` | `Inställningarna är sparade.` | `P_ADMIN` |
| `admin.error.admin_required` | `backend_error_text` | `Administratörsbehörighet krävs.` | `P_ADMIN` |
| `admin.error.forbidden` | `backend_error_text` | `Du har inte behörighet att göra det här.` | `P_ADMIN` |
| `admin.error.user_not_found` | `backend_error_text` | `Användaren kunde inte hittas.` | `P_ADMIN` |
| `admin.error.already_teacher` | `backend_error_text` | `Användaren är redan lärare.` | `P_ADMIN` |
| `admin.error.already_learner` | `backend_error_text` | `Användaren är redan lärande medlem.` | `P_ADMIN` |
| `admin.error.internal_error` | `backend_error_text` | `Något gick fel. Försök igen.` | `P_ADMIN` |
| `media_system.control_plane.title` | `contract_text` | `Mediastatus` | `P_MEDIA` |
| `media_system.control_plane.summary_heading` | `contract_text` | `Översikt` | `P_MEDIA` |
| `media_system.control_plane.refresh_action` | `contract_text` | `Uppdatera` | `P_MEDIA` |
| `media_system.control_plane.loading_status` | `backend_status_text` | `Läser in mediastatus...` | `P_MEDIA` |
| `media_system.control_plane.load_failed_error` | `backend_error_text` | `Mediastatus kunde inte läsas in.` | `P_MEDIA` |
| `media_system.video.loading_status` | `backend_status_text` | `Läser in video...` | `P_MEDIA` |
| `media_system.video.unavailable_status` | `backend_status_text` | `Videon är inte tillgänglig just nu.` | `P_MEDIA` |
| `media_system.video.failed_error` | `backend_error_text` | `Videon kunde inte visas.` | `P_MEDIA` |
| `media_system.audio.loading_status` | `backend_status_text` | `Läser in ljud...` | `P_MEDIA` |
| `media_system.audio.unavailable_status` | `backend_status_text` | `Ljudet är inte tillgängligt just nu.` | `P_MEDIA` |
| `media_system.audio.failed_error` | `backend_error_text` | `Ljudet kunde inte spelas upp.` | `P_MEDIA` |
| `media_system.preview.loading_status` | `backend_status_text` | `Läser in förhandsvisning...` | `P_MEDIA` |
| `media_system.preview.empty_status` | `backend_status_text` | `Ingen förhandsvisning är tillgänglig.` | `P_MEDIA` |
| `media_system.preview.failed_error` | `backend_error_text` | `Förhandsvisningen kunde inte visas.` | `P_MEDIA` |
| `media_system.error.image_load_failed` | `backend_error_text` | `Bilden kunde inte visas.` | `P_MEDIA` |
| `media_system.error.media_not_found` | `backend_error_text` | `Media kunde inte hittas.` | `P_MEDIA` |
| `media_system.error.media_unavailable` | `backend_error_text` | `Media är inte tillgänglig just nu.` | `P_MEDIA` |
| `media_system.error.legacy_media_unavailable` | `backend_error_text` | `Media är inte tillgänglig.` | `P_MEDIA` |
| `media_system.error.storage_access_forbidden` | `backend_error_text` | `Media kunde inte öppnas.` | `P_MEDIA` |
| `media_system.upload.loading_status` | `backend_status_text` | `Förbereder uppladdning...` | `P_MEDIA` |
| `media_system.upload.uploading_status` | `backend_status_text` | `Laddar upp media...` | `P_MEDIA` |
| `media_system.upload.processing_status` | `backend_status_text` | `Media bearbetas...` | `P_MEDIA` |
| `media_system.upload.ready_status` | `backend_status_text` | `Media är redo.` | `P_MEDIA` |
| `media_system.upload.failed_error` | `backend_error_text` | `Media kunde inte laddas upp.` | `P_MEDIA` |
| `media_system.api.error.invalid_media` | `backend_error_text` | `Mediainnehållet är ogiltigt.` | `P_MEDIA` |
| `media_system.api.error.upload_failed` | `backend_error_text` | `Uppladdningen misslyckades.` | `P_MEDIA` |
| `media_system.api.error.resolve_failed` | `backend_error_text` | `Media kunde inte förberedas för visning.` | `P_MEDIA` |
| `media_system.error.resolve_failed` | `backend_error_text` | `Media kunde inte förberedas för visning.` | `P_MEDIA` |
| `media_system.error.runtime_media_missing` | `backend_error_text` | `Media är inte redo för visning ännu.` | `P_MEDIA` |
| `media_system.error.media_processing_failed` | `backend_error_text` | `Media kunde inte bearbetas.` | `P_MEDIA` |

### MVP Shared And Global System

| text_id | authority_class | value_sv | provenance |
|---|---|---|---|
| `mvp_shared.shell.home_label` | `contract_text` | `Hem` | `P_GLOBAL` |
| `mvp_shared.shell.profile_label` | `contract_text` | `Profil` | `P_GLOBAL` |
| `mvp_shared.shell.studio_label` | `contract_text` | `Studio` | `P_GLOBAL` |
| `mvp_shared.shell.logout_action` | `contract_text` | `Logga ut` | `P_GLOBAL` |
| `mvp_shared.auth.login_title` | `contract_text` | `Logga in` | `P_GLOBAL` |
| `mvp_shared.auth.register_action` | `contract_text` | `Skapa konto` | `P_GLOBAL` |
| `mvp_shared.auth.login_action` | `contract_text` | `Logga in` | `P_GLOBAL` |
| `mvp_shared.profile.title` | `contract_text` | `Profil` | `P_GLOBAL` |
| `mvp_shared.profile.save_action` | `contract_text` | `Spara profil` | `P_GLOBAL` |
| `mvp_shared.profile.save_failed_error` | `backend_error_text` | `Profilen kunde inte sparas.` | `P_GLOBAL` |
| `mvp_shared.home.title` | `contract_text` | `Hem` | `P_GLOBAL` |
| `mvp_shared.home.courses_heading` | `contract_text` | `Kurser` | `P_GLOBAL` |
| `mvp_shared.home.feed_heading` | `contract_text` | `Aktuellt` | `P_GLOBAL` |
| `mvp_shared.home.services_heading` | `contract_text` | `Tjänster` | `P_GLOBAL` |
| `mvp_shared.home.load_failed_error` | `backend_error_text` | `Hemvyn kunde inte läsas in.` | `P_GLOBAL` |
| `global_system.not_found.title` | `contract_text` | `Sidan kunde inte hittas` | `P_GLOBAL` |
| `global_system.not_found.body` | `contract_text` | `Kontrollera adressen eller gå tillbaka till startsidan.` | `P_GLOBAL` |
| `global_system.not_found.home_action` | `contract_text` | `Gå till startsidan` | `P_GLOBAL` |
| `global_system.auth_boot.loading_status` | `backend_status_text` | `Förbereder din inloggning...` | `P_GLOBAL` |
| `global_system.auth_boot.failed_error` | `backend_error_text` | `Inloggningen kunde inte förberedas. Försök igen.` | `P_GLOBAL` |
| `global_system.snackbar.generic_success` | `backend_status_text` | `Klart.` | `P_GLOBAL` |
| `global_system.snackbar.generic_failure` | `backend_error_text` | `Något gick fel. Försök igen.` | `P_GLOBAL` |
| `global_system.error.internal` | `backend_error_text` | `Något gick fel. Försök igen om en stund.` | `P_GLOBAL` |
| `global_system.error.unavailable` | `backend_error_text` | `Tjänsten är inte tillgänglig just nu.` | `P_GLOBAL` |
| `global_system.error.network_unavailable` | `backend_error_text` | `Anslutningen saknas. Kontrollera nätverket och försök igen.` | `P_GLOBAL` |
| `global_system.error.unauthenticated` | `backend_error_text` | `Logga in för att fortsätta.` | `P_GLOBAL` |
| `global_system.error.forbidden` | `backend_error_text` | `Du har inte behörighet att göra det här.` | `P_GLOBAL` |
| `global_system.navigation.home_label` | `contract_text` | `Hem` | `P_GLOBAL` |
| `global_system.navigation.back_label` | `contract_text` | `Tillbaka` | `P_GLOBAL` |
| `global_system.navigation.teacher_label` | `contract_text` | `Lärare` | `P_GLOBAL` |
| `global_system.navigation.profile_label` | `contract_text` | `Profil` | `P_GLOBAL` |
| `global_system.brand.name` | `contract_text` | `Aveli` | `P_GLOBAL` |
| `global_system.action.ok` | `backend_status_text` | `Okej` | `P_GLOBAL` |
| `global_system.action.cancel` | `contract_text` | `Avbryt` | `P_GLOBAL` |
| `global_system.action.retry` | `contract_text` | `Försök igen` | `P_GLOBAL` |
| `global_system.action.close` | `contract_text` | `Stäng` | `P_GLOBAL` |

## 5. Non-Populated DB-Owned Fields

The following remain DB-owned and are not catalog values:

- `app.profiles.display_name`
- `app.profiles.bio`
- `auth.users.email`
- `app.courses.title`
- `app.course_public_content.short_description`
- `app.lessons.lesson_title`
- `app.lesson_contents.content_markdown`
- `app.home_player_uploads.title`
- `app.home_player_course_links.title`
- `app.course_bundles.title`

## 6. Non-Populated Identifiers

The following remain non-user-facing identifiers and are not catalog values:

- `identifier.auth.error_code.invalid_credentials`
- `identifier.auth.error_code.unauthenticated`
- `identifier.auth.error_code.validation_error`
- `identifier.auth.error_code.internal_error`
- `identifier.entry_state.onboarding_state`
- `identifier.entry_state.needs_payment`
- `identifier.entry_state.needs_onboarding`
- `identifier.entry_state.can_enter_app`
- `identifier.stripe.session_id`
- `identifier.stripe.client_secret`
- `identifier.stripe.customer_id`
- `identifier.stripe.payment_intent_id`
- `identifier.stripe.subscription_id`
- `identifier.commerce.order_id`
- `identifier.commerce.payment_id`
- `identifier.commerce.provider_reference`
- `identifier.commerce.billing_event_type`
- `identifier.media.media_asset_error_message`
- `identifier.media.media_resolution_failure_reason`
- `identifier.media.control_plane_diagnostic_code`
- `identifier.observability.payment_event_type`
- `identifier.observability.billing_log_event`
- `identifier.observability.media_event_type`
- `identifier.observability.auth_event_type`
- `identifier.mcp.logs_tool_name`
- `identifier.mcp.verification_tool_name`
- `identifier.mcp.media_control_plane_tool_name`
- `identifier.mcp.stripe_observability_tool_name`
- `identifier.mcp.supabase_observability_tool_name`
- `identifier.mcp.netlify_observability_tool_name`

## 7. Blocked Domains Preserved

No values are populated for these blocked targets:

| blocked target | reason |
|---|---|
| `blocked.landing_legal.landing.copy_ownership_missing` | Landing product copy requires exact active contract ownership. |
| `blocked.landing_legal.privacy.copy_ownership_missing` | Privacy copy requires exact active legal contract ownership. |
| `blocked.landing_legal.terms.copy_ownership_missing` | Terms copy requires exact active legal contract ownership. |
| `blocked.landing_legal.gdpr.copy_ownership_missing` | GDPR copy requires exact active legal contract ownership. |
| `blocked.landing_legal.footer.labels_ownership_missing` | Legal navigation labels require exact active contract ownership. |
| `blocked.future.messages.list_contract_missing` | Messages list surface is future-facing without active text contract. |
| `blocked.future.messages.chat_contract_missing` | Chat surface is future-facing without active text contract. |
| `blocked.future.notifications.contract_missing` | Notifications surface is future-facing without active text contract. |
| `blocked.future.events.contract_missing` | Events surface is future-facing without active text contract. |
| `blocked.future.seminars.contract_missing` | Seminars surface is future-facing without active text contract. |
| `blocked.future.session_slots.contract_missing` | Session-slot surface is future-facing without active text contract. |
| `blocked.future.studio_sessions.text_contract_missing` | Studio session text requires active studio-session text contract. |
| `blocked.global_system.english_locale_fallback_forbidden` | English fallback locale is forbidden. |
| `blocked.global_system.frontend_error_authority_forbidden` | Frontend error maps and raw exception text are invalid authority. |

## 8. Final Assertions

- Canonical Swedish values exist for every eligible non-legal concrete catalog
  text ID from TXT-002A.
- `landing_legal` remains blocked and no legal text was invented.
- Future-facing blocked domains remain blocked.
- DB-owned fields were not mutated into catalog values.
- Non-user-facing identifiers were not mutated into catalog values.
- No runtime compliance is claimed.
