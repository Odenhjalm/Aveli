import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('touched home player files do not contain hardcoded product text', () {
    final files = <String>[
      'lib/features/studio/presentation/profile_media_page.dart',
      'lib/features/studio/widgets/home_player_upload_dialog.dart',
      'lib/features/studio/widgets/home_player_upload_routing.dart',
    ];
    final forbiddenSnippets = <String>[
      'Ljud för Home-spelaren',
      'Länkat ljud från kurser',
      'Inga uppladdningar ännu.',
      'Inga länkar ännu.',
      'Namn på ljudfil',
      'Namn på länkat ljud',
      'Välj kursljud att länka',
      'Bearbetar ljud...',
      'Bearbetar ljud…',
      'Kunde inte starta uppladdningen. Försök igen.',
      'Kunde inte spara uppladdningen',
      "replaceFirst('File too large'",
      "Home-spelaren stöder bara ljudfiler.",
      "Endast WAV eller MP3 stöds för ljud i Home-spelaren.",
    ];

    for (final file in files) {
      final content = File(file).readAsStringSync();
      for (final snippet in forbiddenSnippets) {
        expect(
          content.contains(snippet),
          isFalse,
          reason: '$file still contains forbidden product text: $snippet',
        );
      }
    }
  });
}
