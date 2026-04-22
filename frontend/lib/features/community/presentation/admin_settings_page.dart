import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/admin/presentation/admin_shell.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/shared/utils/money.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class AdminSettingsPage extends ConsumerWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(adminSettingsProvider);

    return AdminShell(
      activeDestination: AdminShellDestination.system,
      title: 'System',
      subtitle:
          'Canonical admin metrics, payment rollups, and teacher priorities from /admin/settings',
      statusChipLabel: settings.isLoading
          ? 'Syncing admin settings'
          : settings.hasError
          ? 'Admin settings degraded'
          : 'Admin settings online',
      isNominal: settings.hasValue && !settings.hasError,
      headerTrailing: IconButton(
        tooltip: 'Refresh system metrics',
        onPressed: () => ref.invalidate(adminSettingsProvider),
        icon: const Icon(Icons.refresh_rounded, color: Colors.white),
      ),
      child: settings.when(
        loading: () => const _AdminSettingsLoading(),
        error: (error, stackTrace) => _AdminSettingsError(
          message: error.toString(),
          onRetry: () => ref.invalidate(adminSettingsProvider),
        ),
        data: (state) => _AdminSettingsBody(state: state),
      ),
    );
  }
}

class _AdminSettingsBody extends StatelessWidget {
  const _AdminSettingsBody({required this.state});

  final AdminSettingsState state;

  @override
  Widget build(BuildContext context) {
    final metrics = state.metrics;
    final tiles = <_MetricTileData>[
      _MetricTileData(label: 'Total users', value: '${metrics.totalUsers}'),
      _MetricTileData(
        label: 'Teacher accounts',
        value: '${metrics.totalTeachers}',
      ),
      _MetricTileData(label: 'Courses', value: '${metrics.totalCourses}'),
      _MetricTileData(
        label: 'Published courses',
        value: '${metrics.publishedCourses}',
      ),
      _MetricTileData(
        label: 'Paid orders (30d)',
        value: '${metrics.paidOrders30d}',
      ),
      _MetricTileData(
        label: 'Revenue (30d)',
        value: formatSekFromOre(metrics.revenue30dCents),
      ),
      _MetricTileData(
        label: 'Login events (7d)',
        value: '${metrics.loginEvents7d}',
      ),
      _MetricTileData(
        label: 'Active users (7d)',
        value: '${metrics.activeUsers7d}',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${metrics.totalUsers} users, ${metrics.totalTeachers} teachers, ${metrics.totalCourses} courses',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1180
                ? 4
                : constraints.maxWidth >= 720
                ? 2
                : 1;
            final itemWidth =
                (constraints.maxWidth - ((columns - 1) * 16)) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final tile in tiles)
                  SizedBox(
                    width: itemWidth,
                    child: _MetricTile(data: tile),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        GlassCard(
          padding: const EdgeInsets.all(24),
          opacity: 0.14,
          borderColor: Colors.white.withValues(alpha: 0.12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Teacher priority queue',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                state.priorities.isNotEmpty
                    ? 'Priority entries are rendered directly from /admin/settings.'
                    : 'No teacher priorities are currently present in the admin settings payload.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 18),
              if (state.priorities.isEmpty)
                Text(
                  'No priorities loaded.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                )
              else
                for (
                  var index = 0;
                  index < state.priorities.length;
                  index++
                ) ...[
                  _PriorityRow(priority: state.priorities[index]),
                  if (index != state.priorities.length - 1) ...[
                    const SizedBox(height: 14),
                    Divider(color: Colors.white.withValues(alpha: 0.08)),
                    const SizedBox(height: 14),
                  ],
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricTileData {
  const _MetricTileData({required this.label, required this.value});

  final String label;
  final String value;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.data});

  final _MetricTileData data;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      opacity: 0.12,
      borderColor: Colors.white.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({required this.priority});

  final TeacherPriorityEntry priority;

  @override
  Widget build(BuildContext context) {
    final name = priority.displayName?.trim().isNotEmpty == true
        ? priority.displayName!.trim()
        : priority.email?.trim().isNotEmpty == true
        ? priority.email!.trim()
        : priority.teacherId;
    final courses =
        '${priority.publishedCourses}/${priority.totalCourses} published courses';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              'P${priority.priority}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                courses,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.68),
                ),
              ),
              if (priority.notes?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  priority.notes!.trim(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.56),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminSettingsLoading extends StatelessWidget {
  const _AdminSettingsLoading();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      opacity: 0.14,
      borderColor: Colors.white.withValues(alpha: 0.12),
      child: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Loading canonical admin metrics...',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminSettingsError extends StatelessWidget {
  const _AdminSettingsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      opacity: 0.14,
      borderColor: Colors.redAccent.withValues(alpha: 0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System metrics unavailable',
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
          const SizedBox(height: 18),
          SizedBox(
            width: 220,
            child: GradientButton(
              onPressed: onRetry,
              child: const Text('Retry admin settings'),
            ),
          ),
        ],
      ),
    );
  }
}
