import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/data/models/seminar.dart';
import 'package:wisdom/features/seminars/application/seminar_providers.dart';
import 'package:wisdom/shared/widgets/app_scaffold.dart';
import 'package:wisdom/shared/widgets/glass_card.dart';
import 'package:wisdom/shared/widgets/gradient_button.dart';

import 'seminar_background.dart';

class SeminarDiscoverPage extends ConsumerWidget {
  const SeminarDiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seminarsAsync = ref.watch(publicSeminarsProvider);

    return AppScaffold(
      title: 'Liveseminarier',
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
          tooltip: 'Uppdatera',
          onPressed: () => ref.refresh(publicSeminarsProvider.future),
        ),
      ],
      body: seminarsAsync.when(
        data: (seminars) => ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: seminars.length,
          itemBuilder: (context, index) {
            final seminar = seminars[index];
            return _SeminarListTile(seminar: seminar);
          },
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
                  onPressed: () => ref.refresh(publicSeminarsProvider),
                  child: const Text('Försök igen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeminarListTile extends StatelessWidget {
  const _SeminarListTile({required this.seminar});

  final Seminar seminar;

  @override
  Widget build(BuildContext context) {
    final scheduled = seminar.scheduledAt?.toLocal();
    final countdown = _formatCountdown(scheduled);
    final statusChip = _buildStatusChip(seminar.status);
    final timeLabel = scheduled != null
        ? DateFormat('yyyy-MM-dd HH:mm').format(scheduled)
        : null;

    return GlassCard(
      borderRadius: BorderRadius.circular(22),
      padding: const EdgeInsets.all(20),
      opacity: 0.12,
      borderColor: Colors.transparent,
      onTap: () => context.pushNamed(
        AppRoute.seminarJoin,
        pathParameters: {'id': seminar.id},
      ),
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
                      const SizedBox(height: 6),
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
              GradientButton.tonal(
                onPressed: () => context.pushNamed(
                  AppRoute.seminarJoin,
                  pathParameters: {'id': seminar.id},
                ),
                child: const Text('Gå med'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              if (statusChip != null) statusChip,
              if (timeLabel != null) _infoChip(timeLabel),
              if (countdown != null) _infoChip('Start om $countdown'),
            ],
          ),
        ],
      ),
    );
  }

  Chip? _buildStatusChip(SeminarStatus status) {
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
        return Chip(
          label: const Text('Planerat'),
          backgroundColor: Colors.white.withValues(alpha: 0.18),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        );
      case SeminarStatus.ended:
        return Chip(
          label: const Text('Avslutat'),
          backgroundColor: Colors.white.withValues(alpha: 0.18),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        );
      case SeminarStatus.canceled:
        return Chip(
          label: const Text('Inställt'),
          backgroundColor: Colors.white.withValues(alpha: 0.18),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        );
      case SeminarStatus.draft:
        return null;
    }
  }

  Widget _infoChip(String text) {
    return Chip(
      label: Text(text),
      backgroundColor: Colors.white.withValues(alpha: 0.18),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
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
