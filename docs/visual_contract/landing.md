# Landing

VISUAL CONTRACT (DETERMINISTIC)

### STATE
- `landing_anonymous`

### CONDITIONS
- Browser storage was cleared before observation.
- The app loaded at `https://app.aveli.app/`.
- No authenticated redirect occurred in this clean browser state.
- `UNVERIFIED`: whether any server-side session artifact alone can bypass this state.

### UI
- Aveli logo/button.
- `Logga in` button.
- Hero headline `Upptäck din andliga resa`.
- Hero body copy about learning from spiritual teachers.
- Primary CTA `Bli medlem`.
- Trust text `Över 1000+ nöjda elever`, `Certifierade lärare`, and `14 dagar pröveperiod`.
- Footer/legal buttons `Terms of Service`, `Skapa konto`, `Privacy Policy`, and `Data Deletion`.

### ACTIONS
- `Skapa konto`
- `Logga in`
- `Bli medlem`
- `Terms of Service`
- `Privacy Policy`
- `Data Deletion`

### TRANSITIONS
- `Skapa konto` -> `auth_signup_anonymous`
- `Logga in` -> `UNVERIFIED`
- `Bli medlem` -> `UNVERIFIED`
