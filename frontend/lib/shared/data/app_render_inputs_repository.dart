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
  const AppRenderInputs({required this.brand});

  factory AppRenderInputs.fromJson(Map<String, dynamic> json) {
    _assertExactFields(json, const {'brand'}, 'app.render_inputs');
    return AppRenderInputs(
      brand: BrandRenderInputs.fromJson(
        _requiredMap(json['brand'], fieldName: 'brand'),
      ),
    );
  }

  final BrandRenderInputs brand;

  @override
  List<Object?> get props => [brand];
}

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
