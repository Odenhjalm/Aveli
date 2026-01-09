# Aveli Renaming Notes

Summary
- Flutter package name: renamed to aveli (pubspec and imports).
- App identifiers: Android applicationId/namespace, iOS and macOS bundle IDs, Linux application ID, Windows binary name.
- Deep links: updated legacy scheme usage to aveliapp; updated local media cache dir to aveli_media.
- Branding strings: app widget renamed to AveliApp, gradient copy, checkout hint strings.
- Landing site: titles/footer/support email now use Aveli.

Intentionally unchanged
- WISDOM_* environment variable keys in `frontend/lib/shared/utils/media_kit_support.dart` (deployment compatibility).
- Content/asset slugs that include soulwisdom (backend or content-coupled):
  - `frontend/lib/shared/utils/course_cover_assets.g.dart`
  - `frontend/lib/features/landing/presentation/landing_page.dart`
  - `frontend/test/assets/audio_assets_test.dart`
- Backend schema/table names (out of scope).

Commands run (with outputs)
- `flutter pub get`
  - Got dependencies!
  - 28 packages have newer versions incompatible with dependency constraints.
- `flutter analyze`
  - No issues found!
- `flutter test`
  - All tests passed!
