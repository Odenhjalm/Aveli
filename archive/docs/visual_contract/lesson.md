# Lesson

VISUAL CONTRACT (DETERMINISTIC)

### STATE
- `lesson_route_blocked_authenticated`

### CONDITIONS
- Authentication had already succeeded in the active browser session.
- Entry occurred by clicking a sampled course CTA from `course_list_authenticated_home` or a sampled ongoing-course button from `profile_authenticated_pro_member`.
- Route changed to `#/course/...`.
- `UNVERIFIED`: whether any standalone learner lesson route is reachable from the same session.

### UI
- Page title `Kurs`.
- `Tillbaka` button.
- Aveli logo/button.
- Visible error text `TypeError: Instance of 'minified:aDL': type 'minified:aDL' is not a subtype of type 'List<dynamic>?'`.
- Footer/legal buttons `Hem`, `Terms of Service`, `Privacy Policy`, and `Data Deletion`.

### ACTIONS
- `Tillbaka`
- `Hem`
- `Terms of Service`
- `Privacy Policy`
- `Data Deletion`

### TRANSITIONS
- `Hem` -> `course_list_authenticated_home`
- `Tillbaka` -> `UNVERIFIED`

### STATE
- `lesson_editor_premium_selected`

### CONDITIONS
- Authentication had already succeeded in the active browser session.
- Route was `#/teacher/editor`.
- The selected course was `Utbildning - Spirituell coach del 1 av 3`.
- Lesson row `1 Ditt mediumskap` was active.
- `UNVERIFIED`: whether the visible `checking` media status is transient or stable.

### UI
- Active lesson row `1 Ditt mediumskap`.
- Lesson field `Lektiontitel`.
- Lesson label `Innehåller video`.
- Rich-text toolbar with disabled `Ångra` and `Gör om`.
- Insertion controls `Infoga video`, `Infoga ljud`, `Infoga bild`, and `Infoga PDF`.
- Preview-related text `Medium powerpoint 1 ljud.mp4 Förhandsvisning saknas`.
- Disabled buttons `Spara lektionsinnehåll` and `Återställ`.
- Toggle `Lektionen är introduktion Intro laddas upp till public-media, betalt till course-media.`
- Media row `Medium powerpoint 1 ljud.mp4 Lektionsmedia Position 1 • VIDEO` with status `checking`, disabled `Infoga i lektionen`, and buttons `Ladda ner` and `Ta bort`.

### ACTIONS
- Lesson-row selection
- `Ladda ner original`
- `Infoga video`
- `Infoga ljud`
- `Infoga bild`
- `Infoga PDF`
- `Ladda upp ljud`
- `Ladda ner`
- `Ta bort`
- `Home`
- `Teacher Home`

### TRANSITIONS
- Another lesson-row selection -> `UNVERIFIED`
- `Home` -> `course_list_authenticated_home`
- `Teacher Home` -> `teacher_home_authenticated`

### STATE
- `lesson_editor_intro_selected`

### CONDITIONS
- Authentication had already succeeded in the active browser session.
- Route was `#/teacher/editor`.
- The selected course was `Lär dig tyda tarot`.
- Lesson row `1 Grunden i tarot Intro` was active.

### UI
- Active lesson row `1 Grunden i tarot Intro`.
- Lesson field `Lektiontitel`.
- Labels `Introduktion` and `Innehåller ljud`.
- Rich-text toolbar with disabled `Ångra` and `Gör om`.
- Visible lesson body including the audio line `lektion tarot 1.wav 4:34`, multiple headings/paragraphs, and an image labeled `ChatGPT Image 21 mars 2026 22_50_21.png Stillbild`.
- Disabled buttons `Spara lektionsinnehåll` and `Återställ`.
- Toggle `Lektionen är introduktion Intro laddas upp till public-media, betalt till course-media.` shown as checked.
- Media row `lektion tarot 1.wav Lektionsmedia Position 3 • AUDIO Klar för uppspelning` with `Infoga i lektionen`, `Byt ljud`, `Ladda ner`, and `Ta bort`.
- Media row `ChatGPT Image 21 mars 2026 22_50_21.png Lektionsmedia Position 4 • IMAGE` with `Använd som kursbild`, `Infoga i lektionen`, `Ladda ner`, and `Ta bort`.

### ACTIONS
- Another lesson-row selection
- `Infoga video`
- `Infoga ljud`
- `Infoga bild`
- `Infoga PDF`
- `Ladda upp ljud`
- `Infoga i lektionen`
- `Byt ljud`
- `Använd som kursbild`
- `Ladda ner`
- `Ta bort`
- `Home`
- `Teacher Home`

### TRANSITIONS
- Another lesson-row selection -> `UNVERIFIED`
- `Home` -> `course_list_authenticated_home`
- `Teacher Home` -> `teacher_home_authenticated`
