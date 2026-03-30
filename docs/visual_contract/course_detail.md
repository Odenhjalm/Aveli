# Course Detail

## USER STATES
- Authenticated member entering a course route from the home grid.
- Authenticated member entering a course route from `Pågående kurser` on the profile page.

## UI ELEMENTS
- Page title `Kurs`.
- `Tillbaka` button.
- Aveli button/logo.
- Error text rendered in-page: `TypeError: Instance of 'minified:aDL': type 'minified:aDL' is not a subtype of type 'List<dynamic>?'`
- Footer/legal actions including `Hem`, `Terms of Service`, `Privacy Policy`, and `Data Deletion`.

## ACTIONS
- `Hem` returned to `#/home`.
- `Tillbaka` was visible on the error surface.

## DISABLED / HIDDEN
- No full public description was visible on the observed course route.
- No enrollment CTA was visible on the observed course route.
- No lesson list, unlock state, or protected-content boundary was visible on the observed course route.

## TRANSITIONS
- Clicking `Öppna` from sampled course cards navigated into a `#/course/...` route.
- Clicking an ongoing-course button from the profile page also navigated into a `#/course/...` route.
- Every observed entry into the course route rendered the same TypeError surface instead of a visible detail page.

## RULES
- No successful public course-detail render was observed in this session.
