import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/admin/application/admin_observatorium_provider.dart';
import 'package:aveli/features/admin/presentation/admin_shell.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observatorium = ref.watch(adminObservatoriumProvider);
    final state = observatorium.valueOrNull;

    return AdminShell(
      activeDestination: AdminShellDestination.controlRoom,
      title: 'Observatoriet',
      subtitle: 'Operations observatory - all platform systems at a glance',
      statusChipLabel: state?.statusChipLabel ?? 'Syncing observatory',
      isNominal: state?.isNominal ?? false,
      headerTrailing: IconButton(
        tooltip: 'Refresh control room',
        onPressed: () => ref.invalidate(adminObservatoriumProvider),
        icon: const Icon(Icons.refresh_rounded, color: Colors.white),
      ),
      child: observatorium.when(
        loading: () => const _AdminControlRoomLoading(),
        error: (error, stackTrace) => _AdminControlRoomError(
          message: error.toString(),
          onRetry: () => ref.invalidate(adminObservatoriumProvider),
        ),
        data: (state) => _AdminControlRoomBody(state: state),
      ),
    );
  }
}

class _AdminControlRoomBody extends StatelessWidget {
  const _AdminControlRoomBody({required this.state});

  final AdminObservatoriumState state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final allCards = state.cards;
        if (constraints.maxWidth >= 1220) {
          final cardWidth = (constraints.maxWidth - 48) / 4;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (
                    var index = 0;
                    index < state.primaryCards.length;
                    index++
                  ) ...[
                    SizedBox(
                      width: cardWidth,
                      child: _ObservatoriumCard(
                        card: state.primaryCards[index],
                        compact: false,
                      ),
                    ),
                    if (index != state.primaryCards.length - 1)
                      const SizedBox(width: 16),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _ObservatoriumCard(
                      card: state.secondaryCards.first,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: cardWidth,
                    child: _ObservatoriumCard(
                      card: state.secondaryCards.last,
                      compact: true,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        if (constraints.maxWidth >= 760) {
          final cardWidth = (constraints.maxWidth - 16) / 2;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final card in allCards)
                SizedBox(
                  width: cardWidth,
                  child: _ObservatoriumCard(
                    card: card,
                    compact: !state.primaryCards.contains(card),
                  ),
                ),
            ],
          );
        }

        return Column(
          children: [
            for (final card in allCards) ...[
              _ObservatoriumCard(
                card: card,
                compact: !state.primaryCards.contains(card),
              ),
              if (card != allCards.last) const SizedBox(height: 16),
            ],
          ],
        );
      },
    );
  }
}

class _ObservatoriumCard extends StatelessWidget {
  const _ObservatoriumCard({required this.card, required this.compact});

  final AdminObservatoriumCardState card;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final presentation = _presentationFor(card.id);
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: compact ? 248 : 288),
      child: GlassCard(
        key: ValueKey<String>('admin-card-${card.id}'),
        padding: const EdgeInsets.all(22),
        opacity: 0.14,
        sigmaX: 10,
        sigmaY: 10,
        borderColor: presentation.accent.withValues(alpha: 0.38),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: presentation.accent.withValues(alpha: 0.18),
              ),
              child: Icon(presentation.icon, color: presentation.accent),
            ),
            const SizedBox(height: 16),
            Text(
              card.eyebrow,
              style: theme.textTheme.labelLarge?.copyWith(
                color: presentation.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              card.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              card.summary,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.76),
              ),
            ),
            const SizedBox(height: 14),
            for (final line in card.lines.take(compact ? 4 : 5)) ...[
              _ObservatoriumLine(line: line, color: presentation.accent),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pill in card.pills)
                  _ObservatoriumPill(
                    label: pill.label,
                    enabled: pill.enabled,
                    accent: presentation.accent,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ObservatoriumLine extends StatelessWidget {
  const _ObservatoriumLine({required this.line, required this.color});

  final String line;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            line,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

class _ObservatoriumPill extends StatelessWidget {
  const _ObservatoriumPill({
    required this.label,
    required this.enabled,
    required this.accent,
  });

  final String label;
  final bool enabled;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final background = enabled
        ? accent.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.06);
    final foreground = enabled
        ? Colors.white
        : Colors.white.withValues(alpha: 0.44);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: background,
        border: Border.all(
          color: enabled
              ? accent.withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _AdminControlRoomLoading extends StatelessWidget {
  const _AdminControlRoomLoading();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(28),
      opacity: 0.14,
      borderColor: Colors.white.withValues(alpha: 0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(
            'Syncing canonical admin surfaces...',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Loading /admin/settings and /admin/media/health in parallel.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminControlRoomError extends StatelessWidget {
  const _AdminControlRoomError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(28),
      opacity: 0.14,
      borderColor: Colors.redAccent.withValues(alpha: 0.24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Control room failed to load',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 220,
            child: GradientButton(
              onPressed: onRetry,
              child: const Text('Retry loading'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardPresentation {
  const _CardPresentation({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;
}

_CardPresentation _presentationFor(String cardId) {
  switch (cardId) {
    case 'notifications':
      return const _CardPresentation(
        icon: Icons.notifications_active_outlined,
        accent: Color(0xFFF79AB8),
      );
    case 'auth-system':
      return const _CardPresentation(
        icon: Icons.verified_user_outlined,
        accent: Color(0xFF82C8FF),
      );
    case 'learning-system':
      return const _CardPresentation(
        icon: Icons.school_outlined,
        accent: Color(0xFF9BE6A6),
      );
    case 'system-health':
      return const _CardPresentation(
        icon: Icons.monitor_heart_outlined,
        accent: Color(0xFF87E7E7),
      );
    case 'payments':
      return const _CardPresentation(
        icon: Icons.payments_outlined,
        accent: Color(0xFFF3D27A),
      );
    case 'media-control-plane':
      return const _CardPresentation(
        icon: Icons.perm_media_outlined,
        accent: Color(0xFFC2A0FF),
      );
    default:
      return const _CardPresentation(
        icon: Icons.blur_on_outlined,
        accent: Color(0xFF9FB2D8),
      );
  }
}
