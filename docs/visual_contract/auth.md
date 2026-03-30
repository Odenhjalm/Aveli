# Auth

## USER STATES
- Anonymous signup state.
- Anonymous login state.
- Login submission state where auth buttons became disabled.

## UI ELEMENTS
- Signup view showed `Skapa konto`, fields for `E-postadress`, `Namn`, `Lösenord`, and `Inbjudningskod (valfritt)`.
- Signup view showed buttons `Skapa konto`, `Har du konto? Logga in`, and `Skicka magisk länk (ej tillgängligt)`.
- Login view showed `Logga in`, fields for `E-postadress` and `Lösenord`, plus `Skapa konto` and `Glömt lösenord?`.
- Both auth views kept `Tillbaka` and legal/footer links visible.

## ACTIONS
- Clicking `Har du konto? Logga in` navigated to `#/login`.
- Filling the `.env` E2E credentials and clicking `Logga in` successfully routed the session to `#/teacher`.

## DISABLED / HIDDEN
- During login submission, the main login action, `Skapa konto`, and `Glömt lösenord?` were disabled.
- The signup view exposed a button labeled `Skicka magisk länk (ej tillgängligt)`.
- No course list or authenticated profile content was visible on the auth screens.

## TRANSITIONS
- Landing `Skapa konto` opened the signup form.
- Signup `Har du konto? Logga in` opened the login route.
- Successful login transitioned from `#/login` to `#/teacher`.

## RULES
- No account creation, password reset, or magic-link flow was executed.
