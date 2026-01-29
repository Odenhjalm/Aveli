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

  static const Set<String> _publicPaths = <String>{
    RoutePath.landingRoot,
    RoutePath.landing,
    RoutePath.home,
    RoutePath.privacy,
    RoutePath.terms,
  };

  static GuardContext fromUri(Uri uri) => fromPath(uri.path);

  static GuardContext fromPath(String rawPath) {
    final path = _normalizePath(rawPath);
    if (path.isEmpty) return GuardContext.unknown;
    if (_publicPaths.contains(path)) return GuardContext.publicLanding;
    return GuardContext.appCore;
  }

  static String _normalizePath(String path) {
    if (path.isEmpty) return '';
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }
}
