import 'package:flutter/foundation.dart';

import 'package:aveli/data/models/text_bundle.dart';
import 'package:aveli/editor/document/lesson_document.dart';
import 'package:aveli/shared/utils/resolved_media_contract.dart';

Object? _requireResponseField(Object? payload, String key, String label) {
  switch (payload) {
    case final Map data when data.containsKey(key):
      return data[key];
    case final Map _:
      throw StateError('$label is missing required field: $key');
    default:
      throw StateError('$label returned a non-object payload');
  }
}

String _requiredResponseString(Object? payload, String key, String label) {
  final value = _requireResponseField(payload, key, label);
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw StateError('$label field "$key" must be a non-empty string');
}

String? _nullableResponseString(Object? payload, String key, String label) {
  if (payload is Map && !payload.containsKey(key)) {
    return null;
  }
  final value = _requireResponseField(payload, key, label);
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw StateError('$label field "$key" must be a string or null');
}

int _requiredResponseInt(Object? payload, String key, String label) {
  final value = _requireResponseField(payload, key, label);
  if (value is int) {
    return value;
  }
  throw StateError('$label field "$key" must be an int');
}

bool _requiredResponseBool(Object? payload, String key, String label) {
  final value = _requireResponseField(payload, key, label);
  if (value is bool) {
    return value;
  }
  throw StateError('$label field "$key" must be a bool');
}

List<Object?> _requiredResponseList(Object? payload, String key, String label) {
  final value = _requireResponseField(payload, key, label);
  if (value is List) {
    return List<Object?>.from(value);
  }
  throw StateError('$label field "$key" must be a list');
}

Map<String, Object?>? _nullableResponseMap(
  Object? payload,
  String key,
  String label,
) {
  if (payload is Map && !payload.containsKey(key)) {
    return null;
  }
  final value = _requireResponseField(payload, key, label);
  if (value == null) {
    return null;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw StateError('$label field "$key" must be an object or null');
}

@immutable
class LessonViewSurface {
  LessonViewSurface({
    required this.lesson,
    required this.navigation,
    required this.access,
    required this.progression,
    required List<LessonViewMediaItem> media,
    this.cta,
    this.pricing,
    List<TextBundle> textBundles = const <TextBundle>[],
  }) : media = List<LessonViewMediaItem>.unmodifiable(media),
       textBundles = List<TextBundle>.unmodifiable(textBundles);

  final LessonViewLesson lesson;
  final LessonViewNavigation navigation;
  final LessonViewAccess access;
  final LessonViewProgression progression;
  final List<LessonViewMediaItem> media;
  final LessonViewCTA? cta;
  final LessonViewPricing? pricing;
  final List<TextBundle> textBundles;

  factory LessonViewSurface.fromResponse(
    Object? payload, {
    String label = 'LessonViewSurface',
  }) {
    final ctaPayload = _nullableResponseMap(payload, 'cta', label);
    final pricingPayload = _nullableResponseMap(payload, 'pricing', label);
    return LessonViewSurface(
      lesson: LessonViewLesson.fromResponse(
        _requireResponseField(payload, 'lesson', label),
      ),
      navigation: LessonViewNavigation.fromResponse(
        _requireResponseField(payload, 'navigation', label),
      ),
      access: LessonViewAccess.fromResponse(
        _requireResponseField(payload, 'access', label),
      ),
      cta: ctaPayload == null ? null : LessonViewCTA.fromResponse(ctaPayload),
      pricing: pricingPayload == null
          ? null
          : LessonViewPricing.fromResponse(pricingPayload),
      textBundles: parseTextBundles(
        _requireResponseField(payload, 'text_bundles', label),
        label: label,
      ),
      progression: LessonViewProgression.fromResponse(
        _requireResponseField(payload, 'progression', label),
      ),
      media: _requiredResponseList(
        payload,
        'media',
        label,
      ).map(LessonViewMediaItem.fromResponse).toList(growable: false),
    );
  }
}

@immutable
class LessonViewLesson {
  const LessonViewLesson({
    required this.id,
    required this.courseId,
    required this.lessonTitle,
    required this.position,
    this.contentDocument,
  });

  final String id;
  final String courseId;
  final String lessonTitle;
  final int position;
  final LessonDocument? contentDocument;

  factory LessonViewLesson.fromResponse(Object? payload) {
    final contentPayload = _nullableResponseMap(
      payload,
      'content_document',
      'LessonViewLesson',
    );
    return LessonViewLesson(
      id: _requiredResponseString(payload, 'id', 'LessonViewLesson'),
      courseId: _requiredResponseString(
        payload,
        'course_id',
        'LessonViewLesson',
      ),
      lessonTitle: _requiredResponseString(
        payload,
        'lesson_title',
        'LessonViewLesson',
      ),
      position: _requiredResponseInt(payload, 'position', 'LessonViewLesson'),
      contentDocument: contentPayload == null
          ? null
          : LessonDocument.fromJson(contentPayload),
    );
  }
}

@immutable
class LessonViewNavigation {
  const LessonViewNavigation({
    required this.previousLessonId,
    required this.nextLessonId,
  });

  final String? previousLessonId;
  final String? nextLessonId;

  factory LessonViewNavigation.fromResponse(Object? payload) {
    return LessonViewNavigation(
      previousLessonId: _nullableResponseString(
        payload,
        'previous_lesson_id',
        'LessonViewNavigation',
      ),
      nextLessonId: _nullableResponseString(
        payload,
        'next_lesson_id',
        'LessonViewNavigation',
      ),
    );
  }
}

@immutable
class LessonViewAccess {
  const LessonViewAccess({
    required this.hasAccess,
    required this.isEnrolled,
    required this.isInDrip,
    required this.isPremium,
    required this.canEnroll,
    required this.canPurchase,
  });

  final bool hasAccess;
  final bool isEnrolled;
  final bool isInDrip;
  final bool isPremium;
  final bool canEnroll;
  final bool canPurchase;

  factory LessonViewAccess.fromResponse(Object? payload) {
    return LessonViewAccess(
      hasAccess: _requiredResponseBool(
        payload,
        'has_access',
        'LessonViewAccess',
      ),
      isEnrolled: _requiredResponseBool(
        payload,
        'is_enrolled',
        'LessonViewAccess',
      ),
      isInDrip: _requiredResponseBool(
        payload,
        'is_in_drip',
        'LessonViewAccess',
      ),
      isPremium: _requiredResponseBool(
        payload,
        'is_premium',
        'LessonViewAccess',
      ),
      canEnroll: _requiredResponseBool(
        payload,
        'can_enroll',
        'LessonViewAccess',
      ),
      canPurchase: _requiredResponseBool(
        payload,
        'can_purchase',
        'LessonViewAccess',
      ),
    );
  }
}

@immutable
class LessonViewCTA {
  const LessonViewCTA({
    required this.type,
    this.textId = '',
    required this.enabled,
    this.reasonCode,
    this.reasonText,
    this.price,
    this.action,
  });

  final String type;
  final String textId;
  final bool enabled;
  final String? reasonCode;
  final String? reasonText;
  final Map<String, Object?>? price;
  final Map<String, Object?>? action;

  factory LessonViewCTA.fromResponse(Object? payload) {
    return LessonViewCTA(
      type: _requiredResponseString(payload, 'type', 'LessonViewCTA'),
      textId: _requiredResponseString(payload, 'text_id', 'LessonViewCTA'),
      enabled: _requiredResponseBool(payload, 'enabled', 'LessonViewCTA'),
      reasonCode: _nullableResponseString(
        payload,
        'reason_code',
        'LessonViewCTA',
      ),
      reasonText: _nullableResponseString(
        payload,
        'reason_text',
        'LessonViewCTA',
      ),
      price: _nullableResponseMap(payload, 'price', 'LessonViewCTA'),
      action: _nullableResponseMap(payload, 'action', 'LessonViewCTA'),
    );
  }
}

@immutable
class LessonViewPricing {
  const LessonViewPricing({
    required this.priceAmountCents,
    required this.priceCurrency,
    required this.formatted,
  });

  final int priceAmountCents;
  final String priceCurrency;
  final String formatted;

  factory LessonViewPricing.fromResponse(Object? payload) {
    return LessonViewPricing(
      priceAmountCents: _requiredResponseInt(
        payload,
        'price_amount_cents',
        'LessonViewPricing',
      ),
      priceCurrency: _requiredResponseString(
        payload,
        'price_currency',
        'LessonViewPricing',
      ),
      formatted: _requiredResponseString(
        payload,
        'formatted',
        'LessonViewPricing',
      ),
    );
  }
}

@immutable
class LessonViewProgression {
  const LessonViewProgression({required this.unlocked, required this.reason});

  final bool unlocked;
  final String reason;

  factory LessonViewProgression.fromResponse(Object? payload) {
    return LessonViewProgression(
      unlocked: _requiredResponseBool(
        payload,
        'unlocked',
        'LessonViewProgression',
      ),
      reason: _requiredResponseString(
        payload,
        'reason',
        'LessonViewProgression',
      ),
    );
  }
}

@immutable
class LessonViewMediaItem {
  const LessonViewMediaItem({
    required this.lessonMediaId,
    required this.position,
    required this.mediaType,
    required this.media,
  });

  final String lessonMediaId;
  final int position;
  final String mediaType;
  final ResolvedMediaData media;

  factory LessonViewMediaItem.fromResponse(Object? payload) {
    return LessonViewMediaItem(
      lessonMediaId: _requiredResponseString(
        payload,
        'lesson_media_id',
        'LessonViewMediaItem',
      ),
      position: _requiredResponseInt(
        payload,
        'position',
        'LessonViewMediaItem',
      ),
      mediaType: _requiredResponseString(
        payload,
        'media_type',
        'LessonViewMediaItem',
      ),
      media: _requiredLessonViewMedia(payload),
    );
  }

  static ResolvedMediaData _requiredLessonViewMedia(Object? payload) {
    final value = _requireResponseField(
      payload,
      'media',
      'LessonViewMediaItem',
    );
    if (value is Map) {
      return ResolvedMediaData.fromJson(Map<String, dynamic>.from(value));
    }
    throw StateError('LessonViewMediaItem field "media" must be an object');
  }
}
