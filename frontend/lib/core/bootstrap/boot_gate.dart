import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'boot_bridge.dart';
import 'boot_config.dart';
import 'boot_log.dart';
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

    BootLog.transition(from: 'dart_warmup_start', to: 'dart_allow_first_frame');

    if (kIsWeb) {
      try {
        WidgetsBinding.instance.allowFirstFrame();
      } catch (_) {
        // Best effort; avoid a permanent blank render.
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        BootLog.transition(
          from: 'dart_allow_first_frame',
          to: 'dart_app_ready',
        );
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
