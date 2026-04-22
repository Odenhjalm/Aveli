import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/data/admin_repository.dart';
import 'package:aveli/features/media_control_plane/admin/media_control_plane_providers.dart';
import 'package:aveli/features/media_control_plane/data/media_control_plane_repository.dart';
import 'package:aveli/shared/utils/money.dart';

class AdminObservatoriumPillState {
  const AdminObservatoriumPillState({
    required this.label,
    required this.enabled,
  });

  final String label;
  final bool enabled;
}

class AdminObservatoriumCardState {
  const AdminObservatoriumCardState({
    required this.id,
    required this.title,
    required this.eyebrow,
    required this.summary,
    required this.lines,
    required this.pills,
  });

  final String id;
  final String title;
  final String eyebrow;
  final String summary;
  final List<String> lines;
  final List<AdminObservatoriumPillState> pills;
}

class AdminObservatoriumState {
  const AdminObservatoriumState({
    required this.settings,
    required this.mediaHealth,
    required this.settingsError,
    required this.mediaError,
    required this.primaryCards,
    required this.secondaryCards,
    required this.statusChipLabel,
    required this.isNominal,
  });

  final AdminSettingsState settings;
  final MediaControlPlaneHealthState? mediaHealth;
  final String? settingsError;
  final String? mediaError;
  final List<AdminObservatoriumCardState> primaryCards;
  final List<AdminObservatoriumCardState> secondaryCards;
  final String statusChipLabel;
  final bool isNominal;

  List<AdminObservatoriumCardState> get cards => [
    ...primaryCards,
    ...secondaryCards,
  ];
}

final adminObservatoriumProvider = AutoDisposeFutureProvider<AdminObservatoriumState>((
  ref,
) async {
  final adminRepository = ref.watch(adminRepositoryProvider);
  final mediaRepository = ref.watch(mediaControlPlaneRepositoryProvider);

  AdminSettingsState settings = AdminSettingsState.empty;
  MediaControlPlaneHealthState? mediaHealth;
  String? settingsError;
  String? mediaError;

  await Future.wait<void>([
    () async {
      try {
        settings = AdminSettingsState.fromJson(
          await adminRepository.fetchSettings(),
        );
      } catch (error, stackTrace) {
        settingsError = AppFailure.from(error, stackTrace).message;
      }
    }(),
    () async {
      try {
        mediaHealth = MediaControlPlaneHealthState.fromJson(
          await mediaRepository.fetchHealth(),
        );
      } catch (error, stackTrace) {
        mediaError = AppFailure.from(error, stackTrace).message;
      }
    }(),
  ]);

  final metrics = settings.metrics;
  final topPriority = settings.priorities.isEmpty
      ? null
      : settings.priorities.first;
  final mediaStatus = mediaHealth?.status.toUpperCase() ?? 'UNKNOWN';
  final nominalMedia =
      mediaHealth != null &&
      _isNominalMediaStatus(mediaHealth!.status) &&
      mediaError == null;
  final nominal = settingsError == null && nominalMedia;

  final primaryCards = <AdminObservatoriumCardState>[
    const AdminObservatoriumCardState(
      id: 'notifications',
      title: 'Notifications',
      eyebrow: 'Disabled surface',
      summary:
          'Presentational only in v1. No canonical operator surface is active.',
      lines: [
        'Push digests remain disabled.',
        'Broadcast queue is unavailable.',
        'No write authority is exposed here.',
      ],
      pills: [
        AdminObservatoriumPillState(label: 'Paused', enabled: false),
        AdminObservatoriumPillState(label: 'Preview only', enabled: false),
      ],
    ),
    AdminObservatoriumCardState(
      id: 'auth-system',
      title: 'Auth System',
      eyebrow: 'Live metrics',
      summary:
          '${_count(metrics.totalUsers)} users, ${_count(metrics.totalTeachers)} teachers, ${_count(metrics.loginEvents7d)} login events over 7 days.',
      lines: [
        '${_count(metrics.totalUsers)} total users',
        '${_count(metrics.totalTeachers)} teacher accounts',
        '${_count(metrics.activeUsers7d)} active users in the last 7 days',
        if (settingsError != null) 'Settings feed unavailable: $settingsError',
      ],
      pills: const [
        AdminObservatoriumPillState(label: 'Read only', enabled: true),
        AdminObservatoriumPillState(label: 'Canonical', enabled: true),
      ],
    ),
    AdminObservatoriumCardState(
      id: 'learning-system',
      title: 'Learning System',
      eyebrow: 'Courses and priorities',
      summary:
          '${_count(metrics.totalCourses)} courses tracked with ${_count(metrics.publishedCourses)} published.',
      lines: [
        '${_count(metrics.totalCourses)} total courses',
        '${_count(metrics.publishedCourses)} published courses',
        '${_count(settings.priorities.length)} teacher priorities in queue',
        if (topPriority != null)
          'Lead priority: ${_teacherName(topPriority)} (P${topPriority.priority})',
      ],
      pills: const [
        AdminObservatoriumPillState(label: 'Live metrics', enabled: true),
        AdminObservatoriumPillState(label: 'Priority queue', enabled: true),
      ],
    ),
    AdminObservatoriumCardState(
      id: 'system-health',
      title: 'System Health',
      eyebrow: 'Composite status',
      summary: nominal
          ? 'Admin telemetry and media health are reporting nominal status.'
          : 'One or more admin surfaces are degraded or partially unavailable.',
      lines: [
        'Admin settings: ${settingsError == null ? 'online' : 'degraded'}',
        'Media plane: ${mediaError == null ? mediaStatus : 'UNAVAILABLE'}',
        if (mediaHealth != null)
          'Workspace: ${_prettyLabel(mediaHealth!.workspace)}',
        if (mediaError != null) 'Media health unavailable: $mediaError',
      ],
      pills: [
        AdminObservatoriumPillState(
          label: nominal ? 'Nominal' : 'Degraded',
          enabled: nominal,
        ),
        const AdminObservatoriumPillState(label: 'Observed', enabled: true),
      ],
    ),
  ];

  final media = mediaHealth;
  final secondaryCards = <AdminObservatoriumCardState>[
    AdminObservatoriumCardState(
      id: 'payments',
      title: 'Payments',
      eyebrow: 'Revenue summary',
      summary:
          '${_count(metrics.paidOrders30d)} paid orders in 30 days and ${formatSekFromOre(metrics.revenue30dCents)} in 30-day revenue.',
      lines: [
        '${_count(metrics.paidOrdersTotal)} paid orders total',
        '${_count(metrics.payingCustomersTotal)} paying customers total',
        '${formatSekFromOre(metrics.revenueTotalCents)} revenue total',
        if (settingsError != null)
          'Payment summary unavailable: $settingsError',
      ],
      pills: const [
        AdminObservatoriumPillState(label: 'Summary only', enabled: true),
        AdminObservatoriumPillState(label: 'No operator route', enabled: false),
      ],
    ),
    AdminObservatoriumCardState(
      id: 'media-control-plane',
      title: 'Media Control Plane',
      eyebrow: 'Live admin health',
      summary: media == null
          ? 'Media control health is currently unavailable.'
          : _mediaSummary(media),
      lines: [
        if (media != null) 'Access: ${_prettyLabel(media.access)}',
        if (media != null) 'Capabilities: ${_count(media.capabilities.length)}',
        if (media != null) 'Shortcuts: ${_count(media.actions.length)}',
        if (mediaError != null) 'Health feed unavailable: $mediaError',
      ],
      pills: [
        AdminObservatoriumPillState(
          label: nominalMedia ? 'Ready' : 'Attention',
          enabled: nominalMedia,
        ),
        const AdminObservatoriumPillState(label: 'Admin only', enabled: true),
      ],
    ),
  ];

  return AdminObservatoriumState(
    settings: settings,
    mediaHealth: mediaHealth,
    settingsError: settingsError,
    mediaError: mediaError,
    primaryCards: primaryCards,
    secondaryCards: secondaryCards,
    statusChipLabel: nominal
        ? 'All systems nominal'
        : settingsError != null && mediaError != null
        ? 'Admin telemetry degraded'
        : 'Partial system visibility',
    isNominal: nominal,
  );
});

bool _isNominalMediaStatus(String status) {
  final normalized = status.trim().toLowerCase();
  return normalized == 'ok' || normalized == 'ready';
}

String _count(int value) => value.toString();

String _teacherName(TeacherPriorityEntry entry) {
  final displayName = entry.displayName?.trim();
  if (displayName != null && displayName.isNotEmpty) {
    return displayName;
  }
  final email = entry.email?.trim();
  if (email != null && email.isNotEmpty) {
    return email;
  }
  return entry.teacherId;
}

String _mediaSummary(MediaControlPlaneHealthState mediaHealth) {
  return 'Status ${mediaHealth.status.toUpperCase()} with ${_count(mediaHealth.capabilities.length)} capabilities and ${_count(mediaHealth.actions.length)} shortcuts.';
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
