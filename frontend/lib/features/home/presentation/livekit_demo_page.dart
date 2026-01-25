import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/home/application/livekit_controller.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class LiveKitDemoPage extends ConsumerStatefulWidget {
  const LiveKitDemoPage({super.key});

  @override
  ConsumerState<LiveKitDemoPage> createState() => _LiveKitDemoPageState();
}

class _LiveKitDemoPageState extends ConsumerState<LiveKitDemoPage> {
  final _seminarCtrl = TextEditingController(
    text: '99999999-9999-4999-8999-999999999999',
  );

  @override
  void dispose() {
    _seminarCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveSessionControllerProvider);
    final controller = ref.read(liveSessionControllerProvider.notifier);
    ref.listen<LiveSessionState>(liveSessionControllerProvider, (
      previous,
      next,
    ) {
      final error = next.error;
      if (error != null && error != previous?.error && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('LiveKit: $error')));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('LiveKit demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _seminarCtrl,
              decoration: const InputDecoration(
                labelText: 'Seminar ID',
                helperText: 'Använd seedad seminarie-ID från backend',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                GradientButton.icon(
                  onPressed: state.connecting
                      ? null
                      : () => controller.connect(_seminarCtrl.text.trim()),
                  icon: state.connecting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: const Text('Anslut'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: state.connected || state.connecting
                      ? controller.disconnect
                      : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Koppla från'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusRow(label: 'Status', value: _statusLabel(state)),
                    _StatusRow(label: 'WS URL', value: state.wsUrl ?? '—'),
                    _StatusRow(
                      label: 'Token',
                      value: state.token != null
                          ? '${state.token!.substring(0, 12)}…'
                          : '—',
                    ),
                    if (state.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        state.error!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Expanded(
              child: SingleChildScrollView(
                child: Text(
                  'Efter anslutning visas LiveKit Room-objektstatus ovan. '
                  'Använd `room.remoteParticipants` för att lista deltagare eller bygg vidare på detta demo.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(LiveSessionState state) {
    if (state.connecting) return 'Ansluter…';
    if (state.connected) return 'Ansluten';
    return 'Frånkopplad';
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
