# Playback

VISUAL CONTRACT (DETERMINISTIC)

### STATE
- `playback_idle_home`

### CONDITIONS
- Authentication had already succeeded in the active browser session.
- Route was `#/home`.
- The home-player module was visible before `Spela` was clicked.

### UI
- Cover image.
- Current track text `32 min ceremoni Come Come`.
- Buttons `Bibliotek`, `Föregående`, `Nästa`, and `Spela`.

### ACTIONS
- `Bibliotek`
- `Föregående`
- `Nästa`
- `Spela`

### TRANSITIONS
- `Bibliotek` -> `playback_library_modal`
- `Spela` -> `playback_active_home`
- `Föregående` -> `UNVERIFIED`
- `Nästa` -> `UNVERIFIED`

### STATE
- `playback_library_modal`

### CONDITIONS
- `playback_idle_home` was visible.
- `Bibliotek` was clicked.

### UI
- Dialog title `Bibliotek`.
- Track-count text `12 spår`.
- Close button `Stäng`.
- Twelve visible track buttons including `32 min ceremoni Come Come 32:37`, `jag lyfter 03:47`, `bbc_blackbird-_nhu0510417 01:47`, `Mother Gaia - mantrasong 05:54`, and additional entries.

### ACTIONS
- `Stäng`
- Track-button selection

### TRANSITIONS
- `Stäng` -> `playback_idle_home`
- Track-button selection -> `UNVERIFIED`

### STATE
- `playback_active_home`

### CONDITIONS
- `playback_idle_home` was visible.
- `Spela` was clicked.

### UI
- Main player button changed to `Stoppa`.
- Time/progress group `00:00 / 32:37`.
- Two unlabeled buttons inside the player controls.
- Two visible sliders inside the player controls.
- Existing `Bibliotek`, `Föregående`, and `Nästa` controls remained visible.

### ACTIONS
- `Stoppa`
- `Bibliotek`
- `Föregående`
- `Nästa`
- Slider interaction

### TRANSITIONS
- `Stoppa` -> `UNVERIFIED`
- `Bibliotek` -> `UNVERIFIED`
- `Föregående` -> `UNVERIFIED`
- `Nästa` -> `UNVERIFIED`
- Slider interaction -> `UNVERIFIED`
