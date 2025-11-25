import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/core/env/app_config.dart';

/// Helper for resolving backend-hostade mediaresurser under `/assets`.
class BackendAssetResolver {
  BackendAssetResolver(String baseUrl)
    : _base = baseUrl.isEmpty ? null : Uri.tryParse(baseUrl);

  final Uri? _base;

  /// Build an absolute URL for a backend asset.
  String url(String assetPath) {
    if (assetPath.isEmpty) {
      throw ArgumentError('assetPath may not be empty');
    }
    if (assetPath.startsWith('http://') || assetPath.startsWith('https://')) {
      return assetPath;
    }

    final normalized = _normalize(assetPath);
    if (_base == null) {
      return normalized;
    }
    return _base.resolve(normalized).toString();
  }

  /// Resolve to a network-backed [ImageProvider].
  ImageProvider<Object> imageProvider(String assetPath, {double scale = 1.0}) {
    return NetworkImage(url(assetPath), scale: scale);
  }

  String _normalize(String assetPath) {
    final trimmed = assetPath.trim();
    if (trimmed.startsWith('/assets/')) {
      return trimmed;
    }
    final withoutLeadingSlashes = trimmed.replaceFirst(RegExp(r'^/+'), '');
    return withoutLeadingSlashes.startsWith('assets/')
        ? '/$withoutLeadingSlashes'
        : '/assets/$withoutLeadingSlashes';
  }
}

final backendAssetResolverProvider = Provider<BackendAssetResolver>((ref) {
  final config = ref.watch(appConfigProvider);
  return BackendAssetResolver(config.apiBaseUrl);
});
