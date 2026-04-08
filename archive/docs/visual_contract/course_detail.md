# Course Detail

VISUAL CONTRACT (DETERMINISTIC)

### STATE
- `course_detail_error_authenticated`

### CONDITIONS
- Authentication had already succeeded in the active browser session.
- Entry occurred through a sampled `Öppna` action from `course_list_authenticated_home` or a sampled ongoing-course action from `profile_authenticated_pro_member`.
- Route changed to `#/course/...`.
- `UNVERIFIED`: whether any course route can render a non-error detail state in the same session.

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
