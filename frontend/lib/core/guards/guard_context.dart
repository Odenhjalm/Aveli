import 'package:flutter/foundation.dart';
import 'package:aveli/core/routing/route_paths.dart';

/// Policy context for guarding UI behavior.
///
/// This is intentionally separate from environment resolution (EnvResolver).
/// The environment may be "missing" in a way that matters for some parts of the
/// app (auth/checkout), but should not surface as user-visible banners on
/// public/branded surfaces.
enum GuardContext {
  /// Used when the current route isn't known yet (startup).
  unknown,

  /// Public/branded surfaces (marketing, calm entry points).
  publicLanding,

  /// Application core surfaces where strict guards are allowed.
  appCore,
}

@immutable
class GuardContextResolver {
  const GuardContextResolver._();

  /// Public routes are matched by prefix to survive:
  /// - trailing slashes
  /// - query params
  /// - hash fragments
  /// - router normalization timing during Flutter Web startup
  ///
  /// Note: `/` must be handled via exact equality, otherwise it would match
  /// everything.
  static const List<String> publicRoutePrefixes = <String>[
    RoutePath.landingRoot,
    RoutePath.landing,
    RoutePath.privacy,
    RoutePath.terms,
  ];

  static GuardContext fromUri(Uri uri) {
    return fromLocation(uri.toString());
  }

  static GuardContext fromLocation(String location) {
    final normalizedPath = _normalizeLocationToPath(location);
    if (normalizedPath.isEmpty) return GuardContext.unknown;
    if (normalizedPath == RoutePath.landingRoot) {
      return GuardContext.publicLanding;
    }

    for (final prefix in publicRoutePrefixes) {
      if (prefix == RoutePath.landingRoot) continue;
      if (normalizedPath == prefix || normalizedPath.startsWith('$prefix/')) {
        return GuardContext.publicLanding;
      }
    }

    return GuardContext.appCore;
  }

  static String _normalizeLocationToPath(String location) {
    final parsed = Uri.tryParse(location);
    if (parsed == null) {
      return _normalizePath(location);
    }

    // Hash-based routing encodes the "real" location inside the fragment.
    // Example: https://app.aveli.app/#/landing?x=1
    if (parsed.fragment.startsWith('/')) {
      final fragmentUri = Uri.tryParse(parsed.fragment);
      if (fragmentUri != null) {
        return _normalizePath(fragmentUri.path);
      }
      return _normalizePath(parsed.fragment);
    }

    return _normalizePath(parsed.path);
  }

  static String _normalizePath(String path) {
    if (path.isEmpty) return '';
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }
}
