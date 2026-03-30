# Profile

## USER STATES
- Authenticated user on `#/profile`.
- Profile labels showed `Pro-medlem` and exposed teacher-access navigation (`Teacher Home`).

## UI ELEMENTS
- Heading `Din profil`.
- `Ändra` button.
- Profile-image area with `Ta bort profilbild`.
- Visible identity text: `Lisa Odenhjälm`, `avelibooks@gmail.com`, and `Medlem sedan måndag 19 januari 2026`.
- Membership label `Pro-medlem`.
- `Om mig` section with long bio text.
- `Mina certifikat` section with empty-state text.
- `Mina tjänster` section with `Hantera i Studio`.
- `Pågående kurser` section with multiple course buttons and `Utforska fler`.
- `Min prenumeration` button.
- `Köphistorik` section with `Visa mina köp`.
- `Byt lösenord` section with fields for current password, new password, confirm new password, plus `Uppdatera lösenord`.
- `Logga ut` button.

## ACTIONS
- Clicking an ongoing-course button attempted to open a course route.
- `Hantera i Studio`, `Visa mina köp`, `Min prenumeration`, `Uppdatera lösenord`, and `Logga ut` were visible but not used.

## DISABLED / HIDDEN
- No membership-purchase CTA was visible.
- No disabled profile controls were observed.
- Certificates were empty in the observed state.

## TRANSITIONS
- Home `Profil` navigated to `#/profile`.
- Clicking the sampled ongoing-course button navigated to `#/course/l%C3%A4r-dig-kommunicera-med-djur-eclp-hfq55r41dc`, which rendered the same course TypeError surface.

## RULES
- This surface combined learner-oriented account sections and teacher-oriented navigation in one page.
