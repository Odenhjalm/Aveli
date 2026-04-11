import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/shared/utils/course_cover_contract.dart';

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

Map<String, dynamic> _requireStringKeyedMap(Object? value, String fieldName) {
  switch (value) {
    case final Map<Object?, Object?> data:
      final mapped = <String, dynamic>{};
      for (final entry in data.entries) {
        final key = entry.key;
        if (key is! String) {
          throw StateError('Invalid field type for $fieldName');
        }
        mapped[key] = entry.value;
      }
      return mapped;
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

CourseCoverData? _optionalCourseCover(Object? value, String fieldName) {
  if (value == null) return null;
  return CourseCoverData.fromJson(_requireStringKeyedMap(value, fieldName));
}

@immutable
class LandingCourseCard {
  const LandingCourseCard({
    required this.id,
    required this.slug,
    required this.title,
    required this.step,
    required this.coverMediaId,
    required this.cover,
    required this.priceAmountCents,
    required this.shortDescription,
  });

  final String id;
  final String slug;
  final String title;
  final String step;
  final String? coverMediaId;
  final CourseCoverData? cover;
  final int? priceAmountCents;
  final String? shortDescription;
  String? get resolvedCoverUrl => cover?.resolvedUrl;

  factory LandingCourseCard.fromResponse(Object? payload) {
    return LandingCourseCard(
      id: _requireString(_field(payload, 'id'), 'id'),
      slug: _requireString(_field(payload, 'slug'), 'slug'),
      title: _requireString(_field(payload, 'title'), 'title'),
      step: _requireString(_field(payload, 'step'), 'step'),
      coverMediaId: _optionalString(switch (payload) {
        final Map<Object?, Object?> data => data['cover_media_id'],
        _ => null,
      }, 'cover_media_id'),
      cover: _optionalCourseCover(_field(payload, 'cover'), 'cover'),
      priceAmountCents: _optionalInt(
        _field(payload, 'price_amount_cents'),
        'price_amount_cents',
      ),
      shortDescription: _optionalString(
        _field(payload, 'short_description'),
        'short_description',
      ),
    );
  }
}

@immutable
class LandingTeacher {
  const LandingTeacher({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
    required this.bio,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final String? bio;

  factory LandingTeacher.fromResponse(Object? payload) {
    return LandingTeacher(
      userId: _requireString(_field(payload, 'user_id'), 'user_id'),
      displayName: _requireString(
        _field(payload, 'display_name'),
        'display_name',
      ),
      photoUrl: _optionalString(_field(payload, 'photo_url'), 'photo_url'),
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

Future<T> _unsupportedLandingRuntime<T>() {
  return Future<T>.error(
    UnsupportedError('Landing edge is inert in mounted runtime'),
  );
}

final introCoursesProvider = FutureProvider<LandingSection<LandingCourseCard>>((
  ref,
) {
  return _unsupportedLandingRuntime();
});

final popularCoursesProvider =
    FutureProvider<LandingSection<LandingCourseCard>>((ref) {
      return _unsupportedLandingRuntime();
    });

final teachersProvider = FutureProvider<LandingSection<LandingTeacher>>((ref) {
  return _unsupportedLandingRuntime();
});

final recentServicesProvider = FutureProvider<LandingSection<LandingService>>((
  ref,
) {
  return _unsupportedLandingRuntime();
});
