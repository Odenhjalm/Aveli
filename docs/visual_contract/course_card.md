# Course Card

## USER STATES
- Authenticated member on the `Utforska kurser` grid.

## UI ELEMENTS
- Intro card sample: `Färgernas helande magi` showed visible cover imagery, the label `Introduktion`, a short description, and an `Öppna` CTA.
- Premium card sample: `Utbildning - Spirituell coach del 1 av 3` showed visible cover imagery, the price `800.00 kr`, a short description, and an `Öppna` CTA.
- Each sampled card showed two visible images inside the card group.

## ACTIONS
- Clicking the sampled intro-card CTA attempted to open a course route.
- Clicking the sampled premium-card CTA attempted to open a course route.

## DISABLED / HIDDEN
- No separate `Köp`, `Enroll`, or checkout button was visible on the sampled card faces.
- No lesson list was visible from the card state.

## TRANSITIONS
- Both sampled `Öppna` buttons navigated away from `#/home`.
- The resulting route rendered the course error surface instead of a full course-detail view.

## RULES
- Cover, title, short description, and CTA were all observable directly on the sampled card faces.
- Premium pricing was visible on the sampled premium card and not visible on the sampled intro card.
