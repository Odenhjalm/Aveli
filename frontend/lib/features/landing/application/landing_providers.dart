import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';

String _requireString(Object? value, String fieldName) {
  switch (value) {
    case final String text when text.trim().isNotEmpty:
      return text.trim();
    default:
      throw StateError('Missing required field: $fieldName');
  }
}

String? _optionalString(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final String text:
      final normalized = text.trim();
      return normalized.isEmpty ? null : normalized;
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

int? _optionalInt(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final int number:
      return number;
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

List<Object?> _requireList(Object? value, String fieldName) {
  switch (value) {
    case final List items:
      return List<Object?>.unmodifiable(items);
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

Object? _field(Object? payload, String fieldName) {
  switch (payload) {
    case final Map<Object?, Object?> data when data.containsKey(fieldName):
      return data[fieldName];
    case final Map<Object?, Object?> _:
      throw StateError('Missing required field: $fieldName');
    default:
      throw StateError('Invalid landing payload for $fieldName');
  }
}

@immutable
class LandingTeacher {
  const LandingTeacher({
    required this.id,
    required this.displayName,
    required this.avatarUrl,
    required this.bio,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? bio;

  factory LandingTeacher.fromResponse(Object? payload) {
    return LandingTeacher(
      id: _requireString(_field(payload, 'id'), 'id'),
      displayName: _requireString(
        _field(payload, 'display_name'),
        'display_name',
      ),
      avatarUrl: _optionalString(_field(payload, 'avatar_url'), 'avatar_url'),
      bio: _optionalString(_field(payload, 'bio'), 'bio'),
    );
  }
}

@immutable
class LandingService {
  const LandingService({
    required this.id,
    required this.title,
    required this.description,
    required this.certifiedArea,
    required this.priceCents,
  });

  final String id;
  final String title;
  final String? description;
  final String? certifiedArea;
  final int? priceCents;

  factory LandingService.fromResponse(Object? payload) {
    return LandingService(
      id: _requireString(_field(payload, 'id'), 'id'),
      title: _requireString(_field(payload, 'title'), 'title'),
      description: _optionalString(
        _field(payload, 'description'),
        'description',
      ),
      certifiedArea: _optionalString(
        _field(payload, 'certified_area'),
        'certified_area',
      ),
      priceCents: _optionalInt(_field(payload, 'price_cents'), 'price_cents'),
    );
  }
}

@immutable
class LandingSection<T> {
  const LandingSection({required this.items});

  final List<T> items;

  bool get isEmpty => items.isEmpty;
}

LandingSection<T> _sectionFromResponse<T>(
  Object? payload,
  T Function(Object? payload) parseItem,
) {
  final items = _requireList(
    _field(payload, 'items'),
    'items',
  ).map(parseItem).toList(growable: false);
  return LandingSection<T>(items: items);
}

LandingSection<CourseSummary> landingCourseSectionFromResponse(
  Object? payload,
) {
  return _sectionFromResponse(payload, CourseSummary.fromResponse);
}

Future<LandingSection<T>> _fetchLandingSection<T>(
  Ref ref,
  String path,
  LandingSection<T> Function(Object? payload) parseSection,
) async {
  final client = ref.watch(apiClientProvider);
  try {
    final response = await client.raw.get<Object?>(path);
    return parseSection(response.data);
  } catch (error, stackTrace) {
    throw AppFailure.from(error, stackTrace);
  }
}

final introCoursesProvider = FutureProvider<LandingSection<CourseSummary>>((
  ref,
) {
  return _fetchLandingSection(
    ref,
    '/landing/intro-courses',
    landingCourseSectionFromResponse,
  );
});

final popularCoursesProvider = FutureProvider<LandingSection<CourseSummary>>((
  ref,
) {
  return _fetchLandingSection(
    ref,
    '/landing/popular-courses',
    landingCourseSectionFromResponse,
  );
});

final teachersProvider = FutureProvider<LandingSection<LandingTeacher>>((ref) {
  return _fetchLandingSection(
    ref,
    '/landing/teachers',
    (payload) => _sectionFromResponse(payload, LandingTeacher.fromResponse),
  );
});

final recentServicesProvider = FutureProvider<LandingSection<LandingService>>((
  ref,
) {
  return _fetchLandingSection(
    ref,
    '/landing/services',
    (payload) => _sectionFromResponse(payload, LandingService.fromResponse),
  );
});
