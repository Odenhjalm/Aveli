import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/api/auth_repository.dart';

class BrandLogoRenderInput extends Equatable {
  const BrandLogoRenderInput({required this.resolvedUrl});

  factory BrandLogoRenderInput.fromJson(Map<String, dynamic> json) {
    _assertExactFields(json, const {'resolved_url'}, 'brand.logo');
    final resolvedUrl = (json['resolved_url'] as String? ?? '').trim();
    if (resolvedUrl.isEmpty) {
      throw StateError('Missing brand.logo.resolved_url');
    }
    return BrandLogoRenderInput(resolvedUrl: resolvedUrl);
  }

  final String resolvedUrl;

  @override
  List<Object?> get props => [resolvedUrl];
}

class UiBackgroundRenderInput extends Equatable {
  const UiBackgroundRenderInput({required this.resolvedUrl});

  factory UiBackgroundRenderInput.fromJson(
    Map<String, dynamic> json, {
    required String fieldName,
  }) {
    _assertExactFields(json, const {'resolved_url'}, fieldName);
    final resolvedUrl = (json['resolved_url'] as String? ?? '').trim();
    if (resolvedUrl.isEmpty) {
      throw StateError('Missing $fieldName.resolved_url');
    }
    return UiBackgroundRenderInput(resolvedUrl: resolvedUrl);
  }

  final String resolvedUrl;

  @override
  List<Object?> get props => [resolvedUrl];
}

class UiBackgroundRenderInputs extends Equatable {
  const UiBackgroundRenderInputs({
    required this.defaultBackground,
    required this.lesson,
    required this.observatory,
  });

  factory UiBackgroundRenderInputs.fromJson(Map<String, dynamic> json) {
    _assertExactFields(json, const {
      'default',
      'lesson',
      'observatory',
    }, 'ui.backgrounds');
    return UiBackgroundRenderInputs(
      defaultBackground: UiBackgroundRenderInput.fromJson(
        _requiredMap(json['default'], fieldName: 'ui.backgrounds.default'),
        fieldName: 'ui.backgrounds.default',
      ),
      lesson: UiBackgroundRenderInput.fromJson(
        _requiredMap(json['lesson'], fieldName: 'ui.backgrounds.lesson'),
        fieldName: 'ui.backgrounds.lesson',
      ),
      observatory: UiBackgroundRenderInput.fromJson(
        _requiredMap(
          json['observatory'],
          fieldName: 'ui.backgrounds.observatory',
        ),
        fieldName: 'ui.backgrounds.observatory',
      ),
    );
  }

  final UiBackgroundRenderInput defaultBackground;
  final UiBackgroundRenderInput lesson;
  final UiBackgroundRenderInput observatory;

  @override
  List<Object?> get props => [defaultBackground, lesson, observatory];
}

class UiRenderInputs extends Equatable {
  const UiRenderInputs({required this.backgrounds});

  factory UiRenderInputs.fromJson(Map<String, dynamic> json) {
    _assertExactFields(json, const {'backgrounds'}, 'ui');
    return UiRenderInputs(
      backgrounds: UiBackgroundRenderInputs.fromJson(
        _requiredMap(json['backgrounds'], fieldName: 'ui.backgrounds'),
      ),
    );
  }

  final UiBackgroundRenderInputs backgrounds;

  @override
  List<Object?> get props => [backgrounds];
}

class BrandRenderInputs extends Equatable {
  const BrandRenderInputs({required this.logo});

  factory BrandRenderInputs.fromJson(Map<String, dynamic> json) {
    _assertExactFields(json, const {'logo'}, 'brand');
    return BrandRenderInputs(
      logo: BrandLogoRenderInput.fromJson(
        _requiredMap(json['logo'], fieldName: 'brand.logo'),
      ),
    );
  }

  final BrandLogoRenderInput logo;

  @override
  List<Object?> get props => [logo];
}

class AppRenderInputs extends Equatable {
  const AppRenderInputs({required this.brand, required this.ui});

  factory AppRenderInputs.fromJson(Map<String, dynamic> json) {
    _assertExactFields(json, const {'brand', 'ui'}, 'app.render_inputs');
    return AppRenderInputs(
      brand: BrandRenderInputs.fromJson(
        _requiredMap(json['brand'], fieldName: 'brand'),
      ),
      ui: UiRenderInputs.fromJson(_requiredMap(json['ui'], fieldName: 'ui')),
    );
  }

  final BrandRenderInputs brand;
  final UiRenderInputs ui;

  @override
  List<Object?> get props => [brand, ui];
}

enum UiBackgroundRenderInputKey { defaultBackground, lesson, observatory }

class AppRenderInputsRepository {
  const AppRenderInputsRepository(this._client);

  final ApiClient _client;

  Future<AppRenderInputs> fetchRenderInputs() async {
    final data = await _client.get<Map<String, dynamic>>(
      ApiPaths.appRenderInputs,
      skipAuth: true,
    );
    return AppRenderInputs.fromJson(data);
  }
}

final appRenderInputsRepositoryProvider = Provider<AppRenderInputsRepository>((
  ref,
) {
  return AppRenderInputsRepository(ref.watch(apiClientProvider));
});

final appRenderInputsProvider = FutureProvider<AppRenderInputs>((ref) {
  return ref.watch(appRenderInputsRepositoryProvider).fetchRenderInputs();
});

final brandLogoRenderInputProvider = FutureProvider<BrandLogoRenderInput>((
  ref,
) async {
  final inputs = await ref.watch(appRenderInputsProvider.future);
  return inputs.brand.logo;
});

final uiBackgroundRenderInputProvider =
    FutureProvider.family<UiBackgroundRenderInput, UiBackgroundRenderInputKey>((
      ref,
      key,
    ) async {
      final inputs = await ref.watch(appRenderInputsProvider.future);
      return switch (key) {
        UiBackgroundRenderInputKey.defaultBackground =>
          inputs.ui.backgrounds.defaultBackground,
        UiBackgroundRenderInputKey.lesson => inputs.ui.backgrounds.lesson,
        UiBackgroundRenderInputKey.observatory =>
          inputs.ui.backgrounds.observatory,
      };
    });

Map<String, dynamic> _requiredMap(Object? value, {required String fieldName}) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw StateError('Invalid $fieldName payload');
}

void _assertExactFields(
  Map<String, dynamic> json,
  Set<String> expected,
  String fieldName,
) {
  final actual = json.keys.toSet();
  final missing = expected.difference(actual).toList()..sort();
  final extra = actual.difference(expected).toList()..sort();
  if (missing.isEmpty && extra.isEmpty) return;
  throw StateError(
    '$fieldName contract violation: missing=$missing extra=$extra',
  );
}
