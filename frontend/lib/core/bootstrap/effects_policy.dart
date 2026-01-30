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
/// SAFE is intentionally conservative and targets CPU-only CanvasKit
/// (software/SwiftShader) stability:
/// - ✅ Allowed: background + thumbnails (downscaled, low filterQuality)
/// - ✅ Allowed: simple opacity/borders
/// - ❌ Forbidden: BackdropFilter / ImageFilter.blur
/// - ❌ Forbidden: ShaderMask / shader-driven text or effects
/// - ❌ Forbidden: particles / decorative animations
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
