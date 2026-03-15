import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/media_control_plane/data/media_control_plane_repository.dart';

class MediaControlCapabilityState {
  const MediaControlCapabilityState({
    required this.id,
    required this.label,
    required this.status,
  });

  final String id;
  final String label;
  final String status;

  factory MediaControlCapabilityState.fromJson(Map<String, dynamic> json) {
    return MediaControlCapabilityState(
      id: (json['id'] as String?) ?? 'unknown',
      label: (json['label'] as String?) ?? 'Unnamed capability',
      status: (json['status'] as String?) ?? 'unknown',
    );
  }
}

class MediaControlActionState {
  const MediaControlActionState({
    required this.id,
    required this.label,
    required this.route,
  });

  final String id;
  final String label;
  final String route;

  factory MediaControlActionState.fromJson(Map<String, dynamic> json) {
    return MediaControlActionState(
      id: (json['id'] as String?) ?? 'unknown',
      label: (json['label'] as String?) ?? 'Unnamed action',
      route: (json['route'] as String?) ?? '/',
    );
  }
}

class MediaControlPlaneHealthState {
  const MediaControlPlaneHealthState({
    required this.controlPlane,
    required this.status,
    required this.access,
    required this.workspace,
    required this.viewerId,
    required this.checkedAt,
    required this.capabilities,
    required this.actions,
  });

  final String controlPlane;
  final String status;
  final String access;
  final String workspace;
  final String viewerId;
  final DateTime? checkedAt;
  final List<MediaControlCapabilityState> capabilities;
  final List<MediaControlActionState> actions;

  factory MediaControlPlaneHealthState.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value is! String || value.trim().isEmpty) return null;
      return DateTime.tryParse(value);
    }

    final capabilities = (json['capabilities'] as List? ?? const <dynamic>[])
        .map(
          (item) => MediaControlCapabilityState.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
    final actions = (json['actions'] as List? ?? const <dynamic>[])
        .map(
          (item) => MediaControlActionState.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);

    return MediaControlPlaneHealthState(
      controlPlane: (json['control_plane'] as String?) ?? 'media',
      status: (json['status'] as String?) ?? 'unknown',
      access: (json['access'] as String?) ?? 'unknown',
      workspace: (json['workspace'] as String?) ?? 'unknown',
      viewerId: (json['viewer_id'] as String?) ?? '',
      checkedAt: parseDate(json['checked_at']),
      capabilities: capabilities,
      actions: actions,
    );
  }
}

final mediaControlPlaneRepositoryProvider =
    Provider<MediaControlPlaneRepository>((ref) {
      final client = ref.watch(apiClientProvider);
      return MediaControlPlaneRepository(client);
    });

final mediaControlPlaneHealthProvider =
    AutoDisposeFutureProvider<MediaControlPlaneHealthState>((ref) async {
      try {
        final repo = ref.watch(mediaControlPlaneRepositoryProvider);
        final data = await repo.fetchHealth();
        return MediaControlPlaneHealthState.fromJson(data);
      } catch (error, stackTrace) {
        throw AppFailure.from(error, stackTrace);
      }
    });
