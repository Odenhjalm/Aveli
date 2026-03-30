# Teacher Home

VISUAL CONTRACT (DETERMINISTIC)

### STATE
- `teacher_home_authenticated`

### CONDITIONS
- Authentication had already succeeded in the active browser session.
- This state was observed on `#/teacher` and `#/studio`.
- Visiting `https://app.aveli.app/` while still authenticated redirected to `#/teacher`.
- `UNVERIFIED`: the exact role or permission condition that grants access to this surface.

### UI
- Top navigation with `Home`, `Teacher Home`, and Aveli.
- Heading `Studio för lärare`.
- `Paketpriser` section with `Skapa paket`, existing item `Session Spirituell Healing`, visible status `Aktivt`, value `xx`, and `Kopiera länk`.
- `Media-spelaren` section with helper text and `Öppna spelarens kontrollpanel`.
- `Mina kurser` section with `Skapa kurs` and many course rows, each with a visible `Ta bort kurs` button.
- `Liveseminarier` section with helper text and `Öppna liveseminarier`.
- `Create invitation code` section with `Email`, `Duration`, `Unit Days`, and `Send invitation`.
- Footer buttons `Min profil`, `Terms of Service`, `Privacy Policy`, and `Data Deletion`.

### ACTIONS
- `Home`
- Course-row selection
- `Skapa paket`
- `Kopiera länk`
- `Öppna spelarens kontrollpanel`
- `Skapa kurs`
- `Ta bort kurs`
- `Öppna liveseminarier`
- `Send invitation`
- `Min profil`

### TRANSITIONS
- `Home` -> `course_list_authenticated_home`
- Sampled course-row selection -> `course_editor_empty_lessons_view`
- `Öppna spelarens kontrollpanel` -> `home_player_control_authenticated`
- `Min profil` -> `profile_authenticated_pro_member`
- `Skapa paket` -> `UNVERIFIED`
- `Skapa kurs` -> `UNVERIFIED`
- `Ta bort kurs` -> `UNVERIFIED`
- `Öppna liveseminarier` -> `UNVERIFIED`
- `Send invitation` -> `UNVERIFIED`
