import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wisdom/shared/widgets/app_avatar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import 'package:wisdom/core/errors/app_failure.dart';
import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/features/community/application/community_providers.dart';
import 'package:wisdom/shared/utils/snack.dart';
import 'package:wisdom/shared/widgets/app_scaffold.dart';
import 'package:wisdom/shared/widgets/gradient_button.dart';

class AdminSettingsPage extends ConsumerStatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  ConsumerState<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends ConsumerState<AdminSettingsPage> {
  final Map<String, int> _pendingPriorities = <String, int>{};
  final Set<String> _dirty = <String>{};
  final Set<String> _saving = <String>{};

  void _adoptServerState(AdminSettingsState state) {
    final knownIds = state.priorities.map((e) => e.teacherId).toSet();
    _pendingPriorities.removeWhere((key, _) => !knownIds.contains(key));
    _dirty.removeWhere((key) => !knownIds.contains(key));
    _saving.removeWhere((key) => !knownIds.contains(key));

    for (final entry in state.priorities) {
      if (_dirty.contains(entry.teacherId) ||
          _saving.contains(entry.teacherId)) {
        continue;
      }
      _pendingPriorities[entry.teacherId] = entry.priority;
    }
  }

  void _adjustPriority(String teacherId, int delta) {
    setState(() {
      final current = _pendingPriorities[teacherId] ?? 100;
      final next = math.max(1, current + delta);
      _pendingPriorities[teacherId] = next;
      _dirty.add(teacherId);
    });
  }

  Future<void> _savePriority(TeacherPriorityEntry entry) async {
    final repo = ref.read(adminRepositoryProvider);
    final value = _pendingPriorities[entry.teacherId] ?? entry.priority;
    setState(() {
      _saving.add(entry.teacherId);
    });
    try {
      final response = await repo.updateTeacherPriority(
        teacherId: entry.teacherId,
        priority: value,
      );
      final updated = TeacherPriorityEntry.fromJson(
        Map<String, dynamic>.from(response),
      );
      setState(() {
        _pendingPriorities[entry.teacherId] = updated.priority;
        _dirty.remove(entry.teacherId);
      });
      ref.invalidate(adminSettingsProvider);
      if (mounted) {
        showSnack(context, 'Prioritet uppdaterad.');
      }
    } catch (error, stackTrace) {
      final message = AppFailure.from(error, stackTrace).message;
      if (mounted) {
        showSnack(context, 'Kunde inte spara: $message');
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving.remove(entry.teacherId);
        });
      }
    }
  }

  Future<void> _resetPriority(TeacherPriorityEntry entry) async {
    final repo = ref.read(adminRepositoryProvider);
    setState(() {
      _saving.add(entry.teacherId);
    });
    try {
      final response = await repo.clearTeacherPriority(entry.teacherId);
      final updated = TeacherPriorityEntry.fromJson(
        Map<String, dynamic>.from(response),
      );
      setState(() {
        _pendingPriorities[entry.teacherId] = updated.priority;
        _dirty.remove(entry.teacherId);
      });
      ref.invalidate(adminSettingsProvider);
      if (mounted) {
        showSnack(context, 'Prioritet återställd.');
      }
    } catch (error, stackTrace) {
      final message = AppFailure.from(error, stackTrace).message;
      if (mounted) {
        showSnack(context, 'Kunde inte återställa: $message');
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving.remove(entry.teacherId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(adminSettingsProvider);
    return settings.when(
      loading: () => const AppScaffold(
        title: 'Admininställningar',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppScaffold(
        title: 'Admininställningar',
        body: Center(child: Text(AppFailure.from(error).message)),
      ),
      data: (state) {
        _adoptServerState(state);
        final metrics = state.metrics;
        final priorities = state.priorities;
        return AppScaffold(
          title: 'Admininställningar',
          actions: [
            IconButton(
              tooltip: 'Visa adminöversikt',
              icon: const Icon(Icons.task_alt_outlined),
              onPressed: () => context.goNamed(AppRoute.admin),
            ),
          ],
          body: ListView(
            children: [
              const SizedBox(height: 8),
              const _SectionTitle(
                icon: Icons.insights_outlined,
                title: 'Översikt',
                subtitle: 'Snabb statistik för trafik och betalningar.',
              ),
              _MetricsGrid(metrics: metrics),
              const SizedBox(height: 24),
              const _SectionTitle(
                icon: Icons.tune_outlined,
                title: 'Prioritet för lärarkurser',
                subtitle:
                    'Ange i vilken ordning lärares kurser ska lyftas i katalogen.',
              ),
              if (priorities.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Inga lärare hittades.'),
                  ),
                )
              else
                ...priorities.map(
                  (entry) => _PriorityCard(
                    entry: entry,
                    currentValue:
                        _pendingPriorities[entry.teacherId] ?? entry.priority,
                    onIncrement: () => _adjustPriority(entry.teacherId, -1),
                    onDecrement: () => _adjustPriority(entry.teacherId, 1),
                    onSave: () => _savePriority(entry),
                    onReset: () => _resetPriority(entry),
                    isDirty: _dirty.contains(entry.teacherId),
                    isSaving: _saving.contains(entry.teacherId),
                  ),
                ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
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
    // ignore: unused_local_variable
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics});

  final AdminMetricsState metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numberFormat = NumberFormat.decimalPattern('sv_SE');
    final currencyFormat = NumberFormat.currency(
      locale: 'sv_SE',
      symbol: 'kr',
      decimalDigits: 0,
    );

    String currencyFromCents(int cents) => currencyFormat.format(cents / 100.0);

    final tiles = [
      _MetricData(
        label: 'Totala användare',
        value: numberFormat.format(metrics.totalUsers),
        icon: Icons.people_alt_outlined,
        color: theme.colorScheme.primary,
      ),
      _MetricData(
        label: 'Lärare & admins',
        value: numberFormat.format(metrics.totalTeachers),
        icon: Icons.school_outlined,
        color: theme.colorScheme.secondary,
      ),
      _MetricData(
        label: 'Publicerade kurser',
        value: numberFormat.format(metrics.publishedCourses),
        icon: Icons.menu_book_outlined,
        color: theme.colorScheme.tertiary,
      ),
      _MetricData(
        label: 'Betalda beställningar (30d)',
        value: numberFormat.format(metrics.paidOrders30d),
        icon: Icons.shopping_bag_outlined,
        color: theme.colorScheme.primaryContainer,
      ),
      _MetricData(
        label: 'Betalande kunder (30d)',
        value: numberFormat.format(metrics.payingCustomers30d),
        icon: Icons.verified_user_outlined,
        color: theme.colorScheme.secondaryContainer,
      ),
      _MetricData(
        label: 'Omsättning (30d)',
        value: currencyFromCents(metrics.revenue30dCents),
        icon: Icons.payments_outlined,
        color: theme.colorScheme.primary,
      ),
      _MetricData(
        label: 'Aktiva användare (7d)',
        value: numberFormat.format(metrics.activeUsers7d),
        icon: Icons.auto_graph_outlined,
        color: theme.colorScheme.tertiaryContainer,
      ),
      _MetricData(
        label: 'Totalt intäkter',
        value: currencyFromCents(metrics.revenueTotalCents),
        icon: Icons.account_balance_wallet_outlined,
        color: theme.colorScheme.secondary,
      ),
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: tiles.map((metric) {
        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(metric.icon, color: metric.color),
                      Text(
                        metric.value,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    metric.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _PriorityCard extends StatelessWidget {
  const _PriorityCard({
    required this.entry,
    required this.currentValue,
    required this.onIncrement,
    required this.onDecrement,
    required this.onSave,
    required this.onReset,
    required this.isDirty,
    required this.isSaving,
  });

  final TeacherPriorityEntry entry;
  final int currentValue;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onSave;
  final VoidCallback onReset;
  final bool isDirty;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      if (entry.email != null && entry.email!.isNotEmpty) entry.email!,
      '${entry.publishedCourses} publicerade / ${entry.totalCourses} totalt',
      if (entry.updatedByName != null) 'Senast av ${entry.updatedByName}',
      if (entry.updatedAt != null)
        DateFormat('yyyy-MM-dd HH:mm').format(entry.updatedAt!.toLocal()),
    ]..removeWhere((element) => element.isEmpty);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 2),
                AppAvatar(url: entry.photoUrl, size: 40),
                const SizedBox(width: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.displayName?.isNotEmpty == true
                            ? entry.displayName!
                            : 'Okänd lärare',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle.join(' • '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.4),
                    ),
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Högre prioritet (lägre tal)',
                        onPressed: isSaving ? null : onIncrement,
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          '$currentValue',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Lägre prioritet',
                        onPressed: isSaving ? null : onDecrement,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                if (isSaving)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  GradientButton.icon(
                    onPressed: isDirty ? onSave : null,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Spara'),
                  ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: isSaving ? null : onReset,
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('Återställ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
