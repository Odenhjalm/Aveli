# Playback

## USER STATES
- Authenticated member on `#/home` before playback starts.
- Authenticated member on `#/home` after pressing play.

## UI ELEMENTS
- Before playback: current-track text `32 min ceremoni Come Come`, plus `Bibliotek`, `Föregående`, `Nästa`, and `Spela`.
- After pressing play: the main CTA changed from `Spela` to `Stoppa`.
- After pressing play: a time/progress group became visible with `00:00 / 32:37`, two unlabeled buttons, and two sliders.

## ACTIONS
- Clicking `Spela` entered the playback state.
- `Bibliotek` opened the track list modal from the same home-player area.
- `Föregående` and `Nästa` were visible in the player state.

## DISABLED / HIDDEN
- The progress/timeline control group was not visible before playback started.
- No course or lesson controls were visible inside the playback module.

## TRANSITIONS
- `Spela` changed the surface to `Stoppa` and revealed the progress controls without leaving `#/home`.

## RULES
- Playback observation was limited to starting and viewing the player state; no track deletion or upload actions were performed.
