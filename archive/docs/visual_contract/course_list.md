# Course List

VISUAL CONTRACT (DETERMINISTIC)

### STATE
- `course_list_authenticated_home`

### CONDITIONS
- Authentication had already succeeded in the active browser session.
- Route was `#/home`.
- The same session exposed both learner-facing `Home` content and a visible `Studio` button.
- `UNVERIFIED`: the underlying permission model that makes the `Studio` button visible in this home state.

### UI
- Home-player module with cover image, current track text `32 min ceremoni Come Come`, and buttons `Bibliotek`, `Föregående`, `Nästa`, and `Spela`.
- Section `Utforska kurser` with helper text `Se vad andra gillar just nu.` and a `Visa alla` button.
- Multiple rows of course cards including both `Introduktion` cards and priced premium cards.
- Section `Gemensam vägg` with `Visa allt` and empty text `Inga aktiviteter ännu.`
- Section `Tjänster` with `Visa alla` and empty text `Inga tjänster publicerade just nu.`
- Navigation/footer buttons including `Home`, `Studio`, and `Profil`.

### ACTIONS
- `Bibliotek`
- `Föregående`
- `Nästa`
- `Spela`
- `Visa alla`
- `Studio`
- `Profil`
- Course-card `Öppna`

### TRANSITIONS
- `Bibliotek` -> `playback_library_modal`
- `Spela` -> `playback_active_home`
- `Studio` -> `teacher_home_authenticated`
- `Profil` -> `profile_authenticated_pro_member`
- Sampled course-card `Öppna` -> `course_detail_error_authenticated`
- `Föregående` -> `UNVERIFIED`
- `Nästa` -> `UNVERIFIED`
- `Visa alla` -> `UNVERIFIED`
