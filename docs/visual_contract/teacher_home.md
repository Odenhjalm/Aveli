# Teacher Home

## USER STATES
- Authenticated teacher-capable session after successful login.
- Observed on `#/teacher` and `#/studio`.

## UI ELEMENTS
- Top navigation showed `Home`, `Teacher Home`, and Aveli.
- Header text: `Studio för lärare`.
- `Paketpriser` section with `Skapa paket`, an existing session label `Session Spirituell Healing`, status `Aktivt`, value `xx`, and `Kopiera länk`.
- `Media-spelaren` section with descriptive helper text and `Öppna spelarens kontrollpanel`.
- `Mina kurser` section with `Skapa kurs` and many course rows, each showing a visible `Ta bort kurs` button.
- `Liveseminarier` section with descriptive text and `Öppna liveseminarier`.
- `Create invitation code` section with `Email`, `Duration`, `Unit Days`, and `Send invitation`.
- Footer buttons included `Min profil`, `Terms of Service`, `Privacy Policy`, and `Data Deletion`.

## ACTIONS
- Clicking a course row opened the course editor.
- Clicking `Öppna spelarens kontrollpanel` opened the Home-player control surface.
- `Skapa paket`, `Skapa kurs`, `Ta bort kurs`, `Öppna liveseminarier`, and `Send invitation` were visible but not used.

## DISABLED / HIDDEN
- No anonymous login/signup CTAs were visible.
- No disabled teacher controls were observed on this surface.

## TRANSITIONS
- Visiting `https://app.aveli.app/` while authenticated redirected to `#/teacher`.
- `Home` navigated to `#/home`.
- Clicking a sampled course row navigated to `#/teacher/editor`.
- `Öppna spelarens kontrollpanel` navigated to `#/studio/profile`.

## RULES
- Destructive and outbound actions were visible on this page but were not executed.
