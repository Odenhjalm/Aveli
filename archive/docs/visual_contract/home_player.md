# Home Player

VISUAL CONTRACT (DETERMINISTIC)

### STATE
- `home_player_control_authenticated`

### CONDITIONS
- Authentication had already succeeded in the active browser session.
- `teacher_home_authenticated` was visible.
- `Öppna spelarens kontrollpanel` was clicked.
- Route changed to `#/studio/profile`.
- `UNVERIFIED`: whether this route is reachable by any other entry path.

### UI
- Page title `Home-spelarens bibliotek`.
- Section heading `Media för Home-spelaren`.
- Buttons `Ladda upp` and `Uppdatera`.
- Helper text explaining that uploads here are direct for Home and separate from courses.
- Many media rows with visible type label `Ljud`, a track button, a `Ta bort` button, and a checked switch.
- Section `Länkat från kurser` with `Länka media`, `Uppdatera`, helper text, and empty text `Inga länkar ännu.`
- Footer/legal buttons `Hem`, `Terms of Service`, `Privacy Policy`, and `Data Deletion`.

### ACTIONS
- `Tillbaka`
- `Ladda upp`
- `Uppdatera`
- Track-button selection
- `Ta bort`
- Switch toggle
- `Länka media`
- `Hem`
- `Terms of Service`
- `Privacy Policy`
- `Data Deletion`

### TRANSITIONS
- `Tillbaka` -> `course_list_authenticated_home`
- `Ladda upp` -> `UNVERIFIED`
- `Uppdatera` -> `UNVERIFIED`
- Track-button selection -> `UNVERIFIED`
- `Ta bort` -> `UNVERIFIED`
- Switch toggle -> `UNVERIFIED`
- `Länka media` -> `UNVERIFIED`
- `Hem` -> `UNVERIFIED`
