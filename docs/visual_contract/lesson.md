# Lesson Page

## USER STATES
- Authenticated member with teacher access.
- Direct learner lesson route was not reached in the observed UI paths.
- Teacher-side lesson editing/detail was reached inside `#/teacher/editor`.

## UI ELEMENTS
- No standalone learner lesson page was observed.
- In the editor, a selected lesson for `Lär dig tyda tarot` exposed lesson rows, the field `Lektiontitel`, labels `Introduktion` and `Innehåller ljud`, a rich-text toolbar, media insertion controls, and a long lesson body.
- The sampled selected lesson showed embedded content including `lektion tarot 1.wav 4:34`, multiple headings and paragraphs, and an image labeled `ChatGPT Image 21 mars 2026 22_50_21.png Stillbild`.
- The sampled lesson-media list showed ready items with actions such as `Infoga i lektionen`, `Byt ljud`, `Ladda ner`, `Använd som kursbild`, and `Ta bort`.
- A sampled premium lesson-edit state for `Utbildning - Spirituell coach del 1 av 3` showed `Lektionsvideo`, file name `Medium powerpoint 1 ljud.mp4`, status `checking`, and the text `Förhandsvisning saknas`.

## ACTIONS
- Clicking a lesson row in the editor activated that lesson inside the same editor surface.
- `Infoga video`, `Infoga ljud`, `Infoga bild`, `Infoga PDF`, `Ladda upp ljud`, `Infoga i lektionen`, `Ladda ner`, `Byt ljud`, and `Ta bort` were visible in lesson-edit states but were not used.
- No learner-side lesson CTA was observed.

## DISABLED / HIDDEN
- `Ångra`, `Gör om`, `Spara lektionsinnehåll`, and `Återställ` were observed disabled in the sampled lesson-edit state.
- `Infoga i lektionen` was observed disabled in one premium-media row while its status showed `checking`.
- A learner-facing locked lesson state was not observed.
- A learner-facing unlocked lesson page with dedicated playback/navigation chrome was not observed.

## TRANSITIONS
- Sampled home-route course-entry actions, including `Lär dig tyda tarot`, stopped at the course error surface before any learner lesson UI appeared.
- Inside the editor, clicking a lesson row kept the route on `#/teacher/editor` and swapped the active lesson content in place.
- Some sampled editor courses exposed no lessons, while other sampled editor courses exposed populated lesson rows and full lesson content.

## RULES
- The standalone learner lesson page remains blocked by the currently reachable course route in this session.
- The only full lesson-like surface successfully observed was the teacher-side lesson editor.
