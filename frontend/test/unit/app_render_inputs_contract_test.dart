import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/shared/data/app_render_inputs_repository.dart';

void main() {
  Map<String, dynamic> payload() => {
    'brand': {
      'logo': {'resolved_url': 'https://cdn.test/brand.png'},
    },
    'ui': {
      'backgrounds': {
        'default': {'resolved_url': 'https://cdn.test/default.png'},
        'lesson': {'resolved_url': 'https://cdn.test/lesson.png'},
        'observatory': {'resolved_url': 'https://cdn.test/observatory.png'},
      },
    },
    'text_bundles': [
      {
        'bundle_id': 'global_system.navigation.v1',
        'locale': 'sv-SE',
        'version': 'catalog_v1',
        'hash': 'sha256:test-navigation',
        'texts': {
          'global_system.navigation.home': 'Hem',
          'global_system.navigation.teacher_home': 'Lärarhem',
          'global_system.navigation.profile': 'Profil',
        },
      },
    ],
  };

  test('parses brand and ui background render inputs', () {
    final inputs = AppRenderInputs.fromJson(payload());

    expect(inputs.brand.logo.resolvedUrl, 'https://cdn.test/brand.png');
    expect(
      inputs.ui.backgrounds.defaultBackground.resolvedUrl,
      'https://cdn.test/default.png',
    );
    expect(
      inputs.ui.backgrounds.lesson.resolvedUrl,
      'https://cdn.test/lesson.png',
    );
    expect(
      inputs.ui.backgrounds.observatory.resolvedUrl,
      'https://cdn.test/observatory.png',
    );
    expect(inputs.textBundles.single.bundleId, 'global_system.navigation.v1');
    expect(
      inputs
          .textBundles
          .single
          .texts['global_system.navigation.teacher_home']
          ?.value,
      'Lärarhem',
    );
  });

  test('fails closed when navigation text_bundles are missing', () {
    final data = payload()..remove('text_bundles');

    expect(() => AppRenderInputs.fromJson(data), throwsStateError);
  });

  test('fails closed when ui backgrounds are missing', () {
    final data = payload()..remove('ui');

    expect(() => AppRenderInputs.fromJson(data), throwsStateError);
  });

  test('fails closed when a background resolved_url is blank', () {
    final data = payload();
    data['ui']['backgrounds']['lesson']['resolved_url'] = ' ';

    expect(() => AppRenderInputs.fromJson(data), throwsStateError);
  });

  test('forbids authority fields in background render inputs', () {
    final data = payload();
    data['ui']['backgrounds']['default']['object_path'] =
        'ui/backgrounds/v1/bakgrund.png';

    expect(() => AppRenderInputs.fromJson(data), throwsStateError);
  });
}
