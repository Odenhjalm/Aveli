import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/media_control_plane/admin/media_control_plane_providers.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';

class MediaControlDashboard extends ConsumerWidget {
  const MediaControlDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(mediaControlPlaneHealthProvider);
    return health.when(
      loading: () => AppScaffold(
        title: 'Media Control Plane',
        actions: _buildActions(context, ref, isLoading: true),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppScaffold(
        title: 'Media Control Plane',
        actions: _buildActions(context, ref),
        body: _ErrorState(
          message: AppFailure.from(error).message,
          onRetry: () => ref.invalidate(mediaControlPlaneHealthProvider),
        ),
      ),
      data: (state) => AppScaffold(
        title: 'Media Control Plane',
        actions: _buildActions(context, ref),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(mediaControlPlaneHealthProvider);
            await ref.read(mediaControlPlaneHealthProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _HeroCard(state: state),
              const SizedBox(height: 20),
              _SectionTitle(
                icon: Icons.monitor_heart_outlined,
                title: 'Status',
                subtitle:
                    'Backendstatus, åtkomstnivå och kontrollpunkter för adminytan.',
              ),
              _StatusGrid(state: state),
              const SizedBox(height: 24),
              _SectionTitle(
                icon: Icons.tune_outlined,
                title: 'Kontroller',
                subtitle:
                    'Genvägar till ytor som styr innehåll, åtkomst och drift.',
              ),
              ...state.actions.map((action) => _ActionCard(action: action)),
              const SizedBox(height: 24),
              _SectionTitle(
                icon: Icons.layers_outlined,
                title: 'Aktiva lager',
                subtitle:
                    'Det här kontrollplanet håller ihop runtime-referenser, uppladdningar och diagnosflöden.',
              ),
              ...state.capabilities.map(
                (capability) => _CapabilityCard(capability: capability),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    WidgetRef ref, {
    bool isLoading = false,
  }) {
    return [
      IconButton(
        tooltip: 'Admin',
        onPressed: () => context.goNamed(AppRoute.admin),
        icon: const Icon(Icons.shield_outlined),
      ),
      IconButton(
        tooltip: 'Admininställningar',
        onPressed: () => context.goNamed(AppRoute.adminSettings),
        icon: const Icon(Icons.tune_outlined),
      ),
      IconButton(
        tooltip: 'Uppdatera',
        onPressed: isLoading
            ? null
            : () => ref.invalidate(mediaControlPlaneHealthProvider),
        icon: const Icon(Icons.refresh_rounded),
      ),
    ];
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.state});

  final MediaControlPlaneHealthState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(theme, state.status);
    final checkedAt = state.checkedAt == null
        ? 'Ingen kontrolltid rapporterad'
        : 'Senast kontrollerad ${_formatCheckedAt(state.checkedAt!)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.92),
            theme.colorScheme.surface.withValues(alpha: 0.98),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.perm_media_outlined,
                    color: statusColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Adminstyrning för mediaflödet',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Den här ytan är låst till adminkonton och samlar status, genvägar och kontrollpunkter för media control plane.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HeroPill(
                  icon: Icons.verified_user_outlined,
                  label: 'Åtkomst: ${_prettyLabel(state.access)}',
                ),
                _HeroPill(
                  icon: Icons.route_outlined,
                  label: 'Workspace: ${_prettyLabel(state.workspace)}',
                ),
                _HeroPill(
                  icon: Icons.check_circle_outline,
                  label: 'Status: ${state.status.toUpperCase()}',
                  foreground: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              checkedAt,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusGrid extends StatelessWidget {
  const _StatusGrid({required this.state});

  final MediaControlPlaneHealthState state;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(Theme.of(context), state.status);
    final cards = [
      _StatusCardData(
        icon: Icons.security_outlined,
        label: 'Åtkomst',
        value: _prettyLabel(state.access),
        accent: statusColor,
      ),
      _StatusCardData(
        icon: Icons.dns_outlined,
        label: 'Kontrollplan',
        value: _prettyLabel(state.controlPlane),
        accent: Theme.of(context).colorScheme.primary,
      ),
      _StatusCardData(
        icon: Icons.widgets_outlined,
        label: 'Aktiva lager',
        value: '${state.capabilities.length}',
        accent: Theme.of(context).colorScheme.secondary,
      ),
      _StatusCardData(
        icon: Icons.touch_app_outlined,
        label: 'Snabbkontroller',
        value: '${state.actions.length}',
        accent: Theme.of(context).colorScheme.tertiary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: wide ? 2 : 1,
            childAspectRatio: wide ? 2.5 : 3.4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) => _StatusCard(data: cards[index]),
        );
      },
    );
  }
}

class _StatusCardData {
  const _StatusCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.data});

  final _StatusCardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: data.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(data.icon, color: data.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    data.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action});

  final MediaControlActionState action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.arrow_outward_rounded),
        title: Text(action.label),
        subtitle: Text(action.route),
        trailing: FilledButton(
          onPressed: () => context.go(action.route),
          child: const Text('Öppna'),
        ),
      ),
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.capability});

  final MediaControlCapabilityState capability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(theme, capability.status);
    return Card(
      child: ListTile(
        leading: Icon(Icons.layers_clear_outlined, color: statusColor),
        title: Text(capability.label),
        subtitle: Text('Status: ${capability.status.toUpperCase()}'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            capability.id,
            style: theme.textTheme.labelMedium?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label, this.foreground});

  final IconData icon;
  final String label;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = foreground ?? theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 34),
                const SizedBox(height: 12),
                Text(
                  'Kunde inte ladda Media Control Plane.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Försök igen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _statusColor(ThemeData theme, String status) {
  switch (status.trim().toLowerCase()) {
    case 'ok':
    case 'ready':
      return const Color(0xFF227A4A);
    default:
      return theme.colorScheme.primary;
  }
}

String _prettyLabel(String value) {
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _formatCheckedAt(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month ${local.year} $hour:$minute';
}
