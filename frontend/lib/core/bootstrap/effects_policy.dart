import 'package:flutter/foundation.dart';

enum EffectsPolicy { safe, full }

extension EffectsPolicyParsing on EffectsPolicy {
  static EffectsPolicy? tryParse(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'safe':
        return EffectsPolicy.safe;
      case 'full':
        return EffectsPolicy.full;
    }
    return null;
  }
}

/// RFC: SAFE/FULL policy must be *forcing* (not advisory).
///
/// The policy is set during bootstrap (before first frame) and is not expected
/// to change at runtime.
class EffectsPolicyController {
  static EffectsPolicy _current = EffectsPolicy.full;

  static EffectsPolicy get current => _current;
  static bool get isSafe => _current == EffectsPolicy.safe;
  static bool get isFull => _current == EffectsPolicy.full;

  static void set(EffectsPolicy policy) {
    _current = policy;
    if (kDebugMode) {
      debugPrint('[BOOT] effects_policy=${policy.name}');
    }
  }
}

