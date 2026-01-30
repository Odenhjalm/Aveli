import 'package:flutter/widgets.dart';

import 'boot_bridge.dart';
import 'boot_log.dart';
import 'effects_policy.dart';

class SafeMedia {
  SafeMedia._();

  static bool get enabled => EffectsPolicyController.isSafe;

  static FilterQuality filterQuality({
    FilterQuality full = FilterQuality.high,
  }) {
    return enabled ? FilterQuality.low : full;
  }

  static int? cacheDimension(
    BuildContext context,
    double logicalPixels, {
    int max = 1600,
  }) {
    if (!enabled) return null;
    if (!logicalPixels.isFinite || logicalPixels <= 0) return null;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final px = (logicalPixels * dpr).round();
    if (px <= 0) return null;
    return px.clamp(1, max);
  }

  static ImageProvider<Object> resizedProvider(
    ImageProvider<Object> provider, {
    required int? cacheWidth,
    required int? cacheHeight,
  }) {
    if (!enabled) return provider;
    if (cacheWidth == null && cacheHeight == null) return provider;
    final ImageProvider<Object> baseProvider = provider is ResizeImage
        ? provider.imageProvider
        : provider;
    return ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, baseProvider);
  }

  static void markBackground() {
    _background = true;
    _logIfChanged();
  }

  static void markThumbnails() {
    _thumbnails = true;
    _logIfChanged();
  }

  static bool _background = false;
  static bool _thumbnails = false;
  static String? _lastSignature;

  static void _logIfChanged() {
    if (!enabled) return;

    final rendererMode = BootBridge.rendererMode ?? 'unknown';
    final policy = EffectsPolicyController.current.name;
    final signature =
        '$rendererMode|$policy|bg=$_background|thumb=$_thumbnails';
    if (_lastSignature == signature) return;
    _lastSignature = signature;

    BootLog.event('safe_media_enabled', {
      'renderer_mode': rendererMode,
      'effects_policy': policy,
      'media': {'background': _background, 'thumbnails': _thumbnails},
    });
  }
}
