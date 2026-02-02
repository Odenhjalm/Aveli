import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:aveli/shared/utils/app_images.dart';

import 'boot_bridge.dart';
import 'boot_config.dart';
import 'boot_log.dart';
import 'critical_assets.dart';
import 'effects_policy.dart';

class BootGate extends StatefulWidget {
  const BootGate({super.key, required this.config, required this.child});

  final BootConfig config;
  final Widget child;

  @override
  State<BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<BootGate> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    BootLog.transition(from: 'dart_run_app', to: 'dart_warmup_start');
    EffectsPolicyController.set(widget.config.effectsPolicy);
    final isSafe = EffectsPolicyController.isSafe;

    // In SAFE/CPU fallback we must not block first paint on critical assets.
    if (kIsWeb && isSafe) {
      BootLog.transition(from: 'dart_warmup_start', to: 'dart_allow_first_frame');
      try {
        WidgetsBinding.instance.allowFirstFrame();
      } catch (_) {
        // Best effort; avoid a permanent blank render.
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        BootLog.transition(from: 'dart_allow_first_frame', to: 'dart_app_ready');
        BootBridge.appReady({
          'boot_id': widget.config.bootId,
          'renderer_mode': widget.config.rendererMode,
          'effects_policy': widget.config.effectsPolicy.name,
        });
      });
    }

    Future<bool> warmAsset({
      required String name,
      required ImageProvider provider,
      required String path,
      Duration timeout = const Duration(milliseconds: 4500),
    }) async {
      try {
        await precacheImage(provider, context).timeout(timeout);
        BootLog.criticalAsset(name: name, status: 'loaded', path: path);
        return true;
      } catch (e) {
        BootLog.criticalAsset(
          name: name,
          status: 'fallback',
          path: path,
          error: e,
        );
        return false;
      }
    }

    final bgOk = await warmAsset(
      name: 'background',
      provider: AppImages.background,
      path: AppImages.backgroundPath,
    );
    final logoOk = await warmAsset(
      name: 'logo',
      provider: AppImages.logo,
      path: AppImages.logoPath,
    );
    CriticalAssets.backgroundOk = bgOk;
    CriticalAssets.logoOk = logoOk;

    if (!kIsWeb || !isSafe) {
      BootLog.transition(from: 'dart_warmup_start', to: 'dart_allow_first_frame');
    }

    if (kIsWeb && !isSafe) {
      try {
        WidgetsBinding.instance.allowFirstFrame();
      } catch (_) {
        // Best effort; avoid a permanent blank render.
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        BootLog.transition(from: 'dart_allow_first_frame', to: 'dart_app_ready');
        BootBridge.appReady({
          'boot_id': widget.config.bootId,
          'renderer_mode': widget.config.rendererMode,
          'effects_policy': widget.config.effectsPolicy.name,
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
