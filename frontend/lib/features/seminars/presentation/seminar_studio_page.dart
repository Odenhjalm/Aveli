import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/seminars/application/seminar_providers.dart';
import 'package:aveli/data/models/seminar.dart';
import 'package:aveli/data/repositories/seminar_repository.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

import 'seminar_background.dart';

class SeminarStudioPage extends ConsumerWidget {
  const SeminarStudioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seminarsAsync = ref.watch(hostSeminarsProvider);

    return AppScaffold(
      title: 'Liveseminarium',
      background: const SeminarBackground(),
      extendBodyBehindAppBar: true,
      transparentAppBar: true,
      logoSize: 0,
      contentPadding: const EdgeInsets.fromLTRB(
        16,
        kToolbarHeight + 40,
        16,
        32,
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => ref.refresh(hostSeminarsProvider.future),
          tooltip: 'Uppdatera',
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nytt seminarium'),
      ),
      body: seminarsAsync.when(
        data: (seminars) => RefreshIndicator(
          onRefresh: () => ref.refresh(hostSeminarsProvider.future),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: seminars.length,
            itemBuilder: (context, index) {
              final seminar = seminars[index];
              return _SeminarCard(seminar: seminar);
            },
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Kunde inte läsa seminarier: $error'),
                const SizedBox(height: 12),
                GradientButton(
                  onPressed: () => ref.refresh(hostSeminarsProvider),
                  child: const Text('Försök igen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final titleCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: '45');
    DateTime? scheduled;

    final repository = ref.read(seminarRepositoryProvider);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Skapa seminarium'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Titel'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Beskrivning'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Längd (minuter)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        scheduled != null
                            ? 'Start: ${scheduled!.toLocal()}'
                            : 'Välj starttid',
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final now = DateTime.now();
                        final pickedDate = await showDatePicker(
                          context: context,
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 365)),
                          initialDate: now,
                        );
                        if (pickedDate == null) return;
                        if (!context.mounted) return;
                        final pickedTime = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(now),
                        );
                        if (pickedTime == null) return;
                        scheduled = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        );
                        (context as Element).markNeedsBuild();
                      },
                      child: const Text('Välj…'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: const Text('Skapa'),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    final duration = int.tryParse(durationCtrl.text.trim());

    try {
      final seminar = await repository.createSeminar(
        title: titleCtrl.text.trim(),
        description: descriptionCtrl.text.trim().isEmpty
            ? null
            : descriptionCtrl.text.trim(),
        scheduledAt: scheduled,
        durationMinutes: duration,
      );
      if (!context.mounted) return;
      ref.invalidate(hostSeminarsProvider);
      context.goNamed(
        AppRoute.seminarDetail,
        pathParameters: {'id': seminar.id},
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte skapa seminarium: $error')),
      );
    } finally {
      titleCtrl.dispose();
      descriptionCtrl.dispose();
      durationCtrl.dispose();
    }
  }
}

class _SeminarCard extends StatelessWidget {
  const _SeminarCard({required this.seminar});

  final Seminar seminar;

  @override
  Widget build(BuildContext context) {
    final scheduled = seminar.scheduledAt?.toLocal();
    final countdown = _formatCountdown(scheduled);

    return GlassCard(
      onTap: () => context.goNamed(
        AppRoute.seminarDetail,
        pathParameters: {'id': seminar.id},
      ),
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(22),
      opacity: 0.12,
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      seminar.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (seminar.description != null &&
                        seminar.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        seminar.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => context.goNamed(
                  AppRoute.seminarDetail,
                  pathParameters: {'id': seminar.id},
                ),
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('Detaljer'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _statusChip(seminar.status),
              if (scheduled != null)
                _infoChip('Start ${scheduledFormatted(scheduled)}'),
              if (countdown != null) _infoChip('Start om $countdown'),
              if (seminar.durationMinutes != null)
                _infoChip('${seminar.durationMinutes} min'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(SeminarStatus status) {
    switch (status) {
      case SeminarStatus.live:
        return Chip(
          label: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, color: Colors.red, size: 12),
              SizedBox(width: 4),
              Text('LIVE'),
            ],
          ),
          backgroundColor: Colors.red.withValues(alpha: 0.1),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        );
      case SeminarStatus.scheduled:
        return _infoChip('Planerat');
      case SeminarStatus.ended:
        return _infoChip('Avslutat');
      case SeminarStatus.canceled:
        return _infoChip('Inställt');
      case SeminarStatus.draft:
        return _infoChip('Utkast');
    }
  }

  Widget _infoChip(String label) {
    return Chip(
      label: Text(label),
      backgroundColor: Colors.white.withValues(alpha: 0.18),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  String scheduledFormatted(DateTime time) {
    final date =
        '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$date kl $h:$m';
  }

  String? _formatCountdown(DateTime? scheduled) {
    if (scheduled == null) return null;
    final now = DateTime.now();
    final diff = scheduled.difference(now);
    if (diff.isNegative) return null;
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    if (hours <= 0 && minutes <= 0) {
      return 'mindre än 1 minut';
    }
    if (hours <= 0) {
      return '$minutes min';
    }
    if (minutes == 0) {
      return '$hours h';
    }
    return '$hours h $minutes min';
  }
}
