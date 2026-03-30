# Course List

## USER STATES
- Authenticated member session on `#/home`.
- Same session also exposed teacher access through the `Studio` button.

## UI ELEMENTS
- Top home-player module with cover image, current track text `32 min ceremoni Come Come`, and buttons `Bibliotek`, `Föregående`, `Nästa`, `Spela`.
- `Utforska kurser` heading with helper text `Se vad andra gillar just nu.` and a `Visa alla` button.
- Multiple rows of course cards mixing `Introduktion` cards and priced premium cards.
- `Gemensam vägg` section with `Visa allt` and the empty-state text `Inga aktiviteter ännu.`
- `Tjänster` section with `Visa alla` and the empty-state text `Inga tjänster publicerade just nu.`
- Navigation/footer buttons visible in this state included `Home`, `Studio`, and `Profil`.

## ACTIONS
- `Bibliotek` opened a media-library dialog.
- `Spela` entered the playback state.
- `Studio` opened the teacher dashboard.
- `Profil` opened the profile page.
- Course-card `Öppna` buttons were visible throughout the grid.

## DISABLED / HIDDEN
- Anonymous CTAs such as `Logga in` and `Skapa konto` were not visible here.
- No enrollment or checkout CTA was visible in the list state itself.
- No disabled course-list controls were observed.

## TRANSITIONS
- `Bibliotek` opened a modal dialog over `#/home`.
- `Studio` navigated to `#/studio`.
- `Profil` navigated to `#/profile`.
- Sampled course-card `Öppna` actions left `#/home` and attempted to open a course route.

## RULES
- Intro cards were visible without a price in their observed card text.
- Premium cards were visible with a currency amount in their observed card text.
