# Course Editor

VISUAL CONTRACT (DETERMINISTIC)

### STATE
- `course_editor_empty_lessons_view`

### CONDITIONS
- Authentication had already succeeded in the active browser session.
- Route was `#/teacher/editor`.
- This state was observed after opening `Färgernas helande magi` and `Lär dig kommunicera med djur` from `teacher_home_authenticated`.
- This state was also observed once after opening `Utbildning - Spirituell coach del 1 av 3`.
- `UNVERIFIED`: whether the empty rendering for `Utbildning - Spirituell coach del 1 av 3` was transient or a stable alternate state.

### UI
- `Skapa ny kurs` section with `Titel`, `Beskrivning (valfri)`, and `Skapa kurs`.
- `Välj kurs` area with the selected course shown as a button.
- Section labels `Kursinformation`, `Lektioner i kursen`, and `Quiz`.
- `Lägg till lektion` buttons.
- Empty-state text `Inga lektioner ännu.`
- `Skapa/Hämta quiz` button with empty text `Inget quiz laddat.`
- Top navigation `Home`, `Teacher Home`, and Aveli.

### ACTIONS
- Selected-course button
- `Skapa kurs`
- `Lägg till lektion`
- `Skapa/Hämta quiz`
- `Home`
- `Teacher Home`
- `Min profil`

### TRANSITIONS
- Selected-course button -> `UNVERIFIED`
- `Home` -> `course_list_authenticated_home`
- `Teacher Home` -> `teacher_home_authenticated`
- `Min profil` -> `UNVERIFIED`

### STATE
- `course_editor_course_selector_menu`

### CONDITIONS
- `course_editor_populated_lessons_overview` or another editor state was already visible.
- The selected-course button in the editor was clicked.

### UI
- Popup menu of teacher-owned courses.
- Visible menu items including `Lär dig tyda tarot`, `Utbildning Spirituell coach del 3 av 3`, `Utbildning Spirituell healer del 2 av 3`, `Utbildning Spirituell meditation del 3 av 3 Meditationscoach`, `Utbildning Självläkande örter & nutrition del 1 av 2`, and additional course names.

### ACTIONS
- Course menu-item selection

### TRANSITIONS
- `Lär dig tyda tarot` -> `course_editor_populated_lessons_overview`
- Other visible course menu items -> `UNVERIFIED`

### STATE
- `course_editor_populated_lessons_overview`

### CONDITIONS
- Authentication had already succeeded in the active browser session.
- Route was `#/teacher/editor`.
- The selected course was `Lär dig tyda tarot`.
- This state was observed before selecting a specific lesson row.

### UI
- Course-info controls including `Titel`, `Beskrivning`, course image controls, `Pris (SEK)`, `Introduktionskurs`, `Publicerad`, placement radios, and `Spara kurs`.
- `Lektioner i kursen` list with `1 Grunden i tarot Intro`, `2 Läggningar`, `3 Symbolernas betydelser i tarot`, and `4 Budskapen i tarot Intro`.
- `Lägg till lektion`.
- `Quiz` section with `Skapa/Hämta quiz` and `Inget quiz laddat.`
- Top navigation `Home`, `Teacher Home`, and Aveli.

### ACTIONS
- Selected-course button
- Lesson-row selection
- `Spara kurs`
- `Lägg till lektion`
- `Skapa/Hämta quiz`
- `Home`
- `Teacher Home`

### TRANSITIONS
- Selected-course button -> `course_editor_course_selector_menu`
- `1 Grunden i tarot Intro` -> `lesson_editor_intro_selected`
- `2 Läggningar` -> `UNVERIFIED`
- `3 Symbolernas betydelser i tarot` -> `UNVERIFIED`
- `4 Budskapen i tarot Intro` -> `UNVERIFIED`
- `Home` -> `course_list_authenticated_home`
- `Teacher Home` -> `teacher_home_authenticated`
