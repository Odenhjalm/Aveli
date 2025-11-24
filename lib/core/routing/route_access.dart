import 'package:flutter/foundation.dart';

/// Defines the minimum access level required for a route.
enum RouteAccessLevel { public, authenticated, teacher, admin }

/// Metadata describing access requirements and redirect behaviour for a route.
@immutable
class RouteAccessMeta {
  const RouteAccessMeta({required this.level, this.redirectAuthed = false});

  final RouteAccessLevel level;
  final bool redirectAuthed;
}
