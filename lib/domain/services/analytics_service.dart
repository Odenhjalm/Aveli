import 'dart:async';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class AnalyticsService {
  static final AnalyticsService instance = AnalyticsService._();
  AnalyticsService._();

  FirebaseAnalytics? get _fa {
    try {
      return FirebaseAnalytics.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseCrashlytics? get _crashlytics {
    try {
      return FirebaseCrashlytics.instance;
    } catch (_) {
      return null;
    }
  }

  Future<void> setUserId(String? id) async {
    final fa = _fa;
    if (fa == null) return;
    await fa.setUserId(id: id);
  }

  Future<void> setUserProperty({required String name, String? value}) async {
    final fa = _fa;
    if (fa == null) return;
    await fa.setUserProperty(name: name, value: value);
  }

  Future<void> logEvent(
    String name, {
    Map<String, Object?> parameters = const {},
    bool crashlyticsBreadcrumb = false,
  }) async {
    final fa = _fa;
    if (fa == null) return;
    // Firebase requires non-null values in parameters
    final filtered = <String, Object>{};
    parameters.forEach((key, value) {
      if (value != null) filtered[key] = value;
    });
    await fa.logEvent(
      name: name,
      parameters: filtered.isEmpty ? null : filtered,
    );
    if (crashlyticsBreadcrumb) {
      final crash = _crashlytics;
      if (crash != null) {
        await crash.log(
          'analytics:$name ${filtered.isEmpty ? "" : filtered.toString()}',
        );
      }
    }
  }
}
