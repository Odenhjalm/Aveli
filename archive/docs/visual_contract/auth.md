# Auth

VISUAL CONTRACT (DETERMINISTIC)

### STATE
- `auth_signup_anonymous`

### CONDITIONS
- Reached from `landing_anonymous` by clicking `Skapa konto`.
- No authenticated navigation was visible on this surface.
- `UNVERIFIED`: whether the same state is reachable by a direct route outside the landing flow.

### UI
- Header `Skapa konto`.
- Fields `E-postadress`, `Namn`, `Lösenord`, and `Inbjudningskod (valfritt)`.
- Buttons `Skapa konto`, `Har du konto? Logga in`, and `Skicka magisk länk (ej tillgängligt)`.
- `Tillbaka` button.
- Footer/legal buttons `Terms of Service`, `Privacy Policy`, and `Data Deletion`.

### ACTIONS
- `Skapa konto`
- `Har du konto? Logga in`
- `Skicka magisk länk (ej tillgängligt)`
- `Tillbaka`
- `Terms of Service`
- `Privacy Policy`
- `Data Deletion`

### TRANSITIONS
- `Har du konto? Logga in` -> `auth_login_anonymous`
- `Skapa konto` -> `UNVERIFIED`
- `Skicka magisk länk (ej tillgängligt)` -> `UNVERIFIED`
- `Tillbaka` -> `UNVERIFIED`

### STATE
- `auth_login_anonymous`

### CONDITIONS
- Reached from `auth_signup_anonymous` by clicking `Har du konto? Logga in`.
- Route changed to `#/login`.
- No authenticated navigation was visible on this surface.

### UI
- Header `Logga in`.
- Fields `E-postadress` and `Lösenord`.
- Buttons `Logga in`, `Skapa konto`, and `Glömt lösenord?`.
- Two visible `Tillbaka` buttons in the shell/login layout.
- Footer/legal buttons `Terms of Service`, `Privacy Policy`, and `Data Deletion`.

### ACTIONS
- `Logga in`
- `Skapa konto`
- `Glömt lösenord?`
- `Tillbaka`
- `Terms of Service`
- `Privacy Policy`
- `Data Deletion`

### TRANSITIONS
- `Logga in` with the observed E2E credentials -> `auth_login_submitting`
- `Skapa konto` -> `UNVERIFIED`
- `Glömt lösenord?` -> `UNVERIFIED`
- `Tillbaka` -> `UNVERIFIED`

### STATE
- `auth_login_submitting`

### CONDITIONS
- `auth_login_anonymous` was visible.
- Valid E2E credentials were entered.
- `Logga in` was clicked.
- Route remained `#/login` while submission was in progress.

### UI
- Login form remained visible.
- Primary login button no longer exposed a readable label in the snapshot.
- `Skapa konto` button was visible and disabled.
- `Glömt lösenord?` button was visible and disabled.
- Password textbox still showed the entered password value.

### ACTIONS
- No enabled user-triggered action was observed in this submission state.

### TRANSITIONS
- Successful completion -> `teacher_home_authenticated`
