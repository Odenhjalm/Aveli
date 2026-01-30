import 'package:flutter/foundation.dart';

import 'boot_bridge.dart';
import 'effects_policy.dart';

class BootConfig {
  const BootConfig({
    required this.bootId,
    required this.effectsPolicy,
    required this.rendererMode,
    required this.bootstrapVersion,
  });

  final String bootId;
  final EffectsPolicy effectsPolicy;
  final String rendererMode;
  final String bootstrapVersion;

  static BootConfig load() {
    final jsBootId = BootBridge.bootId;
    final bootId = (jsBootId == null || jsBootId.isEmpty)
        ? 'boot_${DateTime.now().millisecondsSinceEpoch}'
        : jsBootId;

    final defaultPolicy = kIsWeb ? EffectsPolicy.safe : EffectsPolicy.full;
    final policy =
        EffectsPolicyParsing.tryParse(BootBridge.effectsPolicy) ?? defaultPolicy;

    final rendererMode = BootBridge.rendererMode ?? 'unknown';
    final bootstrapVersion = BootBridge.bootstrapVersion ?? 'unknown';

    return BootConfig(
      bootId: bootId,
      effectsPolicy: policy,
      rendererMode: rendererMode,
      bootstrapVersion: bootstrapVersion,
    );
  }
}

