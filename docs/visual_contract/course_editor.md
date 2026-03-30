# Course Editor

## USER STATES
- Authenticated teacher session on `#/teacher/editor`.
- Observed after opening existing courses from the teacher dashboard.
- Observed both with a sparse editor state and with populated editor states for `Utbildning - Spirituell coach del 1 av 3` and `Lär dig tyda tarot`.

## UI ELEMENTS
- `Skapa ny kurs` section with `Titel`, `Beskrivning (valfri)`, and `Skapa kurs`.
- `Välj kurs` area showing the currently selected course as a button.
- Clicking the selected-course button opened a popup menu of teacher-owned courses.
- `Kursinformation` section exposed editable `Titel` and `Beskrivning`, course image controls, `Pris (SEK)`, `Introduktionskurs`, `Publicerad`, placement radios (`Introduktion`, `Steg 1`, `Steg 2`, `Steg 3`), and `Spara kurs`.
- `Lektionsvideo` / lesson-media area surfaced file metadata and `Ladda ner original` when media was present.
- `Lektioner i kursen` exposed populated lesson rows for sampled courses.
- Sampled populated lesson rows included `1 Ditt mediumskap` through `13 Psykometri` for `Utbildning - Spirituell coach del 1 av 3`.
- Sampled populated lesson rows included `1 Grunden i tarot Intro`, `2 Läggningar`, `3 Symbolernas betydelser i tarot`, and `4 Budskapen i tarot Intro` for `Lär dig tyda tarot`.
- Lesson editing controls included `Lektiontitel`, state labels such as `Introduktion` / `Innehåller ljud`, a rich-text toolbar, `Infoga video`, `Infoga ljud`, `Infoga bild`, `Infoga PDF`, `Spara lektionsinnehåll`, `Återställ`, and `Lektionen är introduktion`.
- Lesson-media rows exposed statuses such as `ready` and `checking`, plus actions including `Infoga i lektionen`, `Byt ljud`, `Ladda ner`, `Använd som kursbild`, and `Ta bort`.
- Preview-related text was visible as `Förhandsvisning saknas`.
- `Skapa/Hämta quiz` button and empty-state text `Inget quiz laddat.`
- Top navigation included `Home`, `Teacher Home`, and Aveli.

## ACTIONS
- Opening a course row from the teacher dashboard selected that course in the editor.
- Clicking the selected-course button opened the course-selector popup menu.
- Clicking a lesson row activated that lesson inside the editor.
- `Lägg till lektion`, `Skapa kurs`, `Spara kurs`, `Spara lektionsinnehåll`, and `Skapa/Hämta quiz` were visible but not used.

## DISABLED / HIDDEN
- `Ångra`, `Gör om`, `Spara lektionsinnehåll`, and `Återställ` were observed disabled in the sampled lesson-edit state.
- In one sampled premium-media row, `Infoga i lektionen` was disabled while the status showed `checking`.
- No dedicated button labeled `Preview` or `Förhandsvisning` was observed in the accessible editor UI.

## TRANSITIONS
- Clicking course rows for `Färgernas helande magi`, `Lär dig kommunicera med djur`, and `Utbildning - Spirituell coach del 1 av 3` each opened the editor with that course selected.
- Clicking the selected-course button opened a popup menu rather than leaving the editor route.
- Clicking a lesson row kept the user on `#/teacher/editor` and changed the active lesson inside the same editor surface.
- `Home` returned to `#/home`.
- `Teacher Home` returned to the teacher dashboard.

## RULES
- The editor can show either an empty lesson state or a populated lesson-editing state depending on the selected course.
