# Profile

VISUAL CONTRACT (DETERMINISTIC)

### STATE
- `profile_authenticated_pro_member`

### CONDITIONS
- Authentication had already succeeded in the active browser session.
- Route was `#/profile`.
- Visible labels included `Pro-medlem`.
- The same page also exposed teacher navigation through `Teacher Home`.
- `UNVERIFIED`: whether non-Pro or non-teacher users see the same profile layout.

### UI
- Heading `Din profil`.
- Button `Ändra`.
- Profile-image area with `Ta bort profilbild`.
- Identity text `Lisa Odenhjälm`, `avelibooks@gmail.com`, and `Medlem sedan måndag 19 januari 2026`.
- Label `Pro-medlem`.
- Section `Om mig` with long bio text.
- Section `Mina certifikat` with empty text about no registered certificates.
- Section `Mina tjänster` with `Hantera i Studio`.
- Section `Pågående kurser` with `Utforska fler` and multiple course buttons.
- Button `Min prenumeration`.
- Section `Köphistorik` with `Visa mina köp`.
- Section `Byt lösenord` with `Nuvarande lösenord`, `Nytt lösenord`, `Bekräfta nytt lösenord`, and `Uppdatera lösenord`.
- Button `Logga ut`.

### ACTIONS
- `Ändra`
- `Ta bort profilbild`
- `Hantera i Studio`
- `Utforska fler`
- Ongoing-course button selection
- `Min prenumeration`
- `Visa mina köp`
- `Uppdatera lösenord`
- `Logga ut`
- `Home`
- `Teacher Home`

### TRANSITIONS
- Sampled ongoing-course button selection -> `course_detail_error_authenticated`
- `Hantera i Studio` -> `UNVERIFIED`
- `Utforska fler` -> `UNVERIFIED`
- `Min prenumeration` -> `UNVERIFIED`
- `Visa mina köp` -> `UNVERIFIED`
- `Uppdatera lösenord` -> `UNVERIFIED`
- `Logga ut` -> `UNVERIFIED`
- `Home` -> `UNVERIFIED`
- `Teacher Home` -> `UNVERIFIED`
