import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/effects_backdrop_filter.dart';

enum AdminShellDestination { controlRoom, users, mediaControl, system }

class AdminShell extends StatelessWidget {
  const AdminShell({
    super.key,
    required this.activeDestination,
    required this.title,
    required this.subtitle,
    required this.child,
    this.childHandlesScrolling = false,
    this.headerTrailing,
    this.statusChipLabel = 'All systems nominal',
    this.isNominal = true,
  });

  final AdminShellDestination activeDestination;
  final String title;
  final String subtitle;
  final Widget child;
  final bool childHandlesScrolling;
  final Widget? headerTrailing;
  final String statusChipLabel;
  final bool isNominal;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '',
      disableBack: true,
      showHomeAction: false,
      logoSize: 0,
      useBasePage: false,
      maxContentWidth: 1680,
      contentPadding: EdgeInsets.zero,
      background: FullBleedBackground(
        image: AppImages.observatoriumBackground,
        topOpacity: 0.22,
        sideVignette: 0.24,
        overlayColor: const Color(0x33050B17),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 260,
                        child: _AdminSidebar(
                          activeDestination: activeDestination,
                          statusChipLabel: statusChipLabel,
                          isNominal: isNominal,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: _AdminContentPanel(
                          title: title,
                          subtitle: subtitle,
                          headerTrailing: headerTrailing,
                          childHandlesScrolling: childHandlesScrolling,
                          child: child,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AdminMobileNav(
                        activeDestination: activeDestination,
                        statusChipLabel: statusChipLabel,
                        isNominal: isNominal,
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: _AdminContentPanel(
                          title: title,
                          subtitle: subtitle,
                          headerTrailing: headerTrailing,
                          childHandlesScrolling: childHandlesScrolling,
                          child: child,
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _AdminContentPanel extends StatelessWidget {
  const _AdminContentPanel({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.childHandlesScrolling,
    this.headerTrailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool childHandlesScrolling;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    return _AdminFrostedPanel(
      color: const Color(0x80101929),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 760;
                return stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _AdminTitleBlock(title: title, subtitle: subtitle),
                          if (headerTrailing != null) ...[
                            const SizedBox(height: 16),
                            headerTrailing!,
                          ],
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _AdminTitleBlock(
                              title: title,
                              subtitle: subtitle,
                            ),
                          ),
                          if (headerTrailing != null) ...[
                            const SizedBox(width: 20),
                            headerTrailing!,
                          ],
                        ],
                      );
              },
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            color: Colors.white.withValues(alpha: 0.08),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: childHandlesScrolling
                ? child
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                    child: child,
                  ),
          ),
        ],
      ),
    );
  }
}

class _AdminTitleBlock extends StatelessWidget {
  const _AdminTitleBlock({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.displaySmall?.copyWith(
            color: Colors.white,
            fontFamily: 'PlayfairDisplay',
            fontWeight: FontWeight.w700,
            height: 0.95,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.78),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.activeDestination,
    required this.statusChipLabel,
    required this.isNominal,
  });

  final AdminShellDestination activeDestination;
  final String statusChipLabel;
  final bool isNominal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _AdminFrostedPanel(
      color: const Color(0x99101724),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image(image: AppImages.logo, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aveli',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Observatorium',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.64),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in _navEntries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AdminNavButton(
                      entry: entry,
                      active: entry.destination == activeDestination,
                    ),
                  ),
              ],
            ),
          ),
          _AdminStatusChip(label: statusChipLabel, isNominal: isNominal),
        ],
      ),
    );
  }
}

class _AdminMobileNav extends StatelessWidget {
  const _AdminMobileNav({
    required this.activeDestination,
    required this.statusChipLabel,
    required this.isNominal,
  });

  final AdminShellDestination activeDestination;
  final String statusChipLabel;
  final bool isNominal;

  @override
  Widget build(BuildContext context) {
    return _AdminFrostedPanel(
      color: const Color(0x8C101724),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Observatorium',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in _navEntries) ...[
                  _AdminMobileNavChip(
                    entry: entry,
                    active: entry.destination == activeDestination,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _AdminStatusChip(label: statusChipLabel, isNominal: isNominal),
        ],
      ),
    );
  }
}

class _AdminNavButton extends StatelessWidget {
  const _AdminNavButton({required this.entry, required this.active});

  final _AdminNavEntry entry;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final foreground = active
        ? Colors.white
        : Colors.white.withValues(alpha: 0.8);
    final background = active
        ? const Color(0xFF7CC8F7).withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.04);
    final border = active
        ? const Color(0xFF7CC8F7).withValues(alpha: 0.38)
        : Colors.white.withValues(alpha: 0.08);
    final key = entry.enabled
        ? ValueKey<String>('admin-nav-${entry.key}')
        : ValueKey<String>('admin-nav-disabled-${entry.key}');

    final child = AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(entry.icon, size: 18, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.label,
              style: TextStyle(
                color: foreground,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
          if (!entry.enabled)
            Icon(
              Icons.block_outlined,
              size: 16,
              color: Colors.white.withValues(alpha: 0.38),
            ),
        ],
      ),
    );

    if (!entry.enabled) {
      return Opacity(opacity: 0.58, child: child);
    }

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.goNamed(entry.routeName!),
      child: child,
    );
  }
}

class _AdminMobileNavChip extends StatelessWidget {
  const _AdminMobileNavChip({required this.entry, required this.active});

  final _AdminNavEntry entry;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final key = entry.enabled
        ? ValueKey<String>('admin-nav-${entry.key}')
        : ValueKey<String>('admin-nav-disabled-${entry.key}');

    final chip = Material(
      key: key,
      color: active
          ? const Color(0xFF8ED4FC).withValues(alpha: 0.2)
          : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: entry.enabled ? () => context.goNamed(entry.routeName!) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                entry.icon,
                size: 16,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Text(
                entry.label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              if (!entry.enabled) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.block_outlined,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.42),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (entry.enabled) {
      return chip;
    }
    return Opacity(opacity: 0.58, child: chip);
  }
}

class _AdminStatusChip extends StatelessWidget {
  const _AdminStatusChip({required this.label, required this.isNominal});

  final String label;
  final bool isNominal;

  @override
  Widget build(BuildContext context) {
    final accent = isNominal
        ? const Color(0xFF8FE7C1)
        : const Color(0xFFFFD27A);
    return Container(
      key: const ValueKey<String>('admin-status-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminFrostedPanel extends StatelessWidget {
  const _AdminFrostedPanel({
    required this.child,
    required this.color,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(28));
    return ClipRRect(
      borderRadius: radius,
      child: EffectsBackdropFilter(
        sigmaX: 18,
        sigmaY: 18,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: radius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 28,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _AdminNavEntry {
  const _AdminNavEntry({
    required this.key,
    required this.label,
    required this.icon,
    this.routeName,
    this.destination,
    this.enabled = true,
  });

  final String key;
  final String label;
  final IconData icon;
  final String? routeName;
  final AdminShellDestination? destination;
  final bool enabled;
}

const List<_AdminNavEntry> _navEntries = [
  _AdminNavEntry(
    key: 'control-room',
    label: 'Control Room',
    icon: Icons.space_dashboard_rounded,
    routeName: AppRoute.admin,
    destination: AdminShellDestination.controlRoom,
  ),
  _AdminNavEntry(
    key: 'users',
    label: 'Users',
    icon: Icons.group_outlined,
    routeName: AppRoute.adminUsers,
    destination: AdminShellDestination.users,
  ),
  _AdminNavEntry(
    key: 'courses',
    label: 'Courses',
    icon: Icons.menu_book_outlined,
    enabled: false,
  ),
  _AdminNavEntry(
    key: 'live-events',
    label: 'Live Events',
    icon: Icons.podcasts_outlined,
    enabled: false,
  ),
  _AdminNavEntry(
    key: 'media-control',
    label: 'Media Control',
    icon: Icons.perm_media_outlined,
    routeName: AppRoute.adminMedia,
    destination: AdminShellDestination.mediaControl,
  ),
  _AdminNavEntry(
    key: 'notifications',
    label: 'Notifications',
    icon: Icons.notifications_outlined,
    enabled: false,
  ),
  _AdminNavEntry(
    key: 'payments',
    label: 'Payments',
    icon: Icons.payments_outlined,
    enabled: false,
  ),
  _AdminNavEntry(
    key: 'system',
    label: 'System',
    icon: Icons.tune_outlined,
    routeName: AppRoute.adminSettings,
    destination: AdminShellDestination.system,
  ),
];
