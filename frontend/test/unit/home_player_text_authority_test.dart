import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('touched home player files do not contain hardcoded product text', () {
    final files = <String>[
      'lib/features/studio/presentation/profile_media_page.dart',
      'lib/features/studio/widgets/home_player_upload_dialog.dart',
      'lib/features/studio/widgets/home_player_upload_routing.dart',
      'lib/features/home/data/home_audio_repository.dart',
      'lib/features/home/presentation/widgets/home_audio_section.dart',
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
      'Kunde inte starta uppladdningen. Försök igen.',
      'Kunde inte spara uppladdningen',
      'Du har inte behörighet att hantera uppladdningen i Home-spelaren.',
      "replaceFirst('File too large'",
      'Home-spelaren stöder bara ljudfiler.',
      'Endast WAV, MP3 eller M4A stöds för ljud i Home-spelaren.',
      'Home-spelarens ljud kunde inte läsas in. Försök igen.',
      'Du har inte behörighet att öppna Home-spelarens ljud.',
      'Ljud i Home-spelaren',
      'Dina uppladdningar och kurslänkar visas här när de är tillgängliga.',
      'Inget ljud är redo ännu.',
      'När ditt ljud är klart visas det här.',
      'Ditt ljud',
      'Från kurs',
      'Ljudet förbereds.',
      'Ljudet bearbetas.',
      'Redo att spela',
      'Ljudet kunde inte spelas upp just nu.',
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
