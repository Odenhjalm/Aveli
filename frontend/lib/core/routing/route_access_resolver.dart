import 'package:aveli/core/routing/route_access.dart';
import 'package:aveli/core/routing/route_manifest.dart';

RouteAccessLevel resolveRouteAccessLevel(String path) {
  final normalized = _normalizePath(path);
  for (final entry in routeManifest) {
    if (_matchesPattern(entry.path, normalized)) {
      return entry.access;
    }
  }
  return RouteAccessLevel.authenticated;
}

String _normalizePath(String path) {
  if (path.isEmpty) return '/';
  var normalized = path.trim();
  final queryIndex = normalized.indexOf('?');
  if (queryIndex >= 0) {
    normalized = normalized.substring(0, queryIndex);
  }
  if (!normalized.startsWith('/')) {
    normalized = '/$normalized';
  }
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool _matchesPattern(String pattern, String path) {
  final patternSegments = _segments(pattern);
  final pathSegments = _segments(path);
  if (patternSegments.length != pathSegments.length) return false;
  for (var i = 0; i < patternSegments.length; i++) {
    final expected = patternSegments[i];
    if (expected.startsWith(':')) continue;
    if (expected != pathSegments[i]) return false;
  }
  return true;
}

List<String> _segments(String path) {
  final trimmed = path.replaceAll(RegExp(r'^/+|/+$'), '');
  if (trimmed.isEmpty) return const <String>[];
  return trimmed.split('/');
}

