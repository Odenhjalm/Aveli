import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import 'package:aveli/data/repositories/sfu_repository.dart';
import 'package:aveli/domain/services/analytics_service.dart';
import 'package:aveli/domain/services/logging_service.dart';
import 'package:aveli/shared/utils/error_messages.dart';

class LiveSessionState {
  const LiveSessionState({
    this.connecting = false,
    this.connected = false,
    this.error,
    this.room,
    this.wsUrl,
    this.token,
    this.screenShareEnabled = false,
  });

  final bool connecting;
  final bool connected;
  final String? error;
  final Room? room;
  final String? wsUrl;
  final String? token;
  final bool screenShareEnabled;

  LiveSessionState copyWith({
    bool? connecting,
    bool? connected,
    String? error,
    Room? room,
    String? wsUrl,
    String? token,
    bool? screenShareEnabled,
  }) {
    return LiveSessionState(
      connecting: connecting ?? this.connecting,
      connected: connected ?? this.connected,
      error: error,
      room: room ?? this.room,
      wsUrl: wsUrl ?? this.wsUrl,
      token: token ?? this.token,
      screenShareEnabled: screenShareEnabled ?? this.screenShareEnabled,
    );
  }
}

class LiveSessionController extends AutoDisposeNotifier<LiveSessionState> {
  late final SfuRepository _repository;

  @override
  LiveSessionState build() {
    ref.keepAlive();
    _repository = ref.watch(sfuRepositoryProvider);
    ref.onDispose(_cleanupRoom);
    return const LiveSessionState();
  }

  Future<void> connect(
    String seminarId, {
    bool micEnabled = true,
    bool cameraEnabled = true,
  }) async {
    if (state.connecting || state.connected) return;
    final trimmedId = seminarId.trim();
    state = state.copyWith(connecting: true, error: null);

    if (trimmedId.isEmpty) {
      const message = 'Ange ett giltigt seminarie-ID.';
      state = state.copyWith(
        connecting: false,
        connected: false,
        error: message,
        screenShareEnabled: false,
      );
      LoggingService.instance.logError(
        'livekit_connect_invalid_id',
        extras: {'seminar_id': seminarId},
      );
      return;
    }

    try {
      final tokenResponse = await _repository.fetchToken(trimmedId);
      if (tokenResponse.wsUrl.isEmpty || tokenResponse.token.isEmpty) {
        const message = 'LiveKit-svar saknar token eller WS-url.';
        state = state.copyWith(
          connecting: false,
          connected: false,
          error: message,
          screenShareEnabled: false,
        );
        LoggingService.instance.logError(
          'livekit_token_invalid',
          extras: {
            'seminar_id': trimmedId,
            'ws_url_empty': tokenResponse.wsUrl.isEmpty,
            'token_empty': tokenResponse.token.isEmpty,
          },
        );
        await _cleanupRoom();
        return;
      }
      unawaited(
        AnalyticsService.instance.logEvent(
          'livekit_token_fetched',
          parameters: {'seminar_id': trimmedId},
        ),
      );
      await _connectUsing(
        tokenResponse.wsUrl,
        tokenResponse.token,
        micEnabled: micEnabled,
        cameraEnabled: cameraEnabled,
      );
    } catch (error, stack) {
      final message = friendlyHttpError(error);
      state = state.copyWith(
        connecting: false,
        connected: false,
        error: message,
        screenShareEnabled: false,
      );
      LoggingService.instance.logError(
        'livekit_connect_failed',
        error: error,
        stackTrace: stack,
        extras: {'seminar_id': trimmedId},
      );
      unawaited(
        AnalyticsService.instance.logEvent(
          'livekit_connect_failed',
          parameters: {'seminar_id': trimmedId, 'error': message},
          crashlyticsBreadcrumb: true,
        ),
      );
      await _cleanupRoom();
    }
  }

  Future<void> connectWithToken({
    required String wsUrl,
    required String token,
    bool micEnabled = true,
    bool cameraEnabled = true,
  }) async {
    if (state.connecting || state.connected) return;
    state = state.copyWith(connecting: true, error: null);
    final trimmedUrl = wsUrl.trim();
    final trimmedToken = token.trim();
    if (trimmedUrl.isEmpty || trimmedToken.isEmpty) {
      const message = 'LiveKit-token eller url saknas.';
      state = state.copyWith(
        connecting: false,
        connected: false,
        error: message,
        screenShareEnabled: false,
      );
      LoggingService.instance.logError(
        'livekit_connect_with_token_invalid_input',
        extras: {
          'ws_url_empty': trimmedUrl.isEmpty,
          'token_empty': trimmedToken.isEmpty,
        },
      );
      await _cleanupRoom();
      return;
    }
    try {
      await _connectUsing(
        trimmedUrl,
        trimmedToken,
        micEnabled: micEnabled,
        cameraEnabled: cameraEnabled,
      );
    } catch (error, stack) {
      final message = friendlyHttpError(error);
      state = state.copyWith(
        connecting: false,
        connected: false,
        error: message,
        screenShareEnabled: false,
      );
      LoggingService.instance.logError(
        'livekit_connect_with_token_failed',
        error: error,
        stackTrace: stack,
      );
      unawaited(
        AnalyticsService.instance.logEvent(
          'livekit_connect_with_token_failed',
          parameters: {'error': message},
          crashlyticsBreadcrumb: true,
        ),
      );
      await _cleanupRoom();
    }
  }

  Future<void> disconnect() async {
    if (!state.connected && !state.connecting) return;
    await _cleanupRoom();
    state = const LiveSessionState();
    unawaited(AnalyticsService.instance.logEvent('livekit_disconnect'));
  }

  Future<void> _connectUsing(
    String wsUrl,
    String token, {
    required bool micEnabled,
    required bool cameraEnabled,
  }) async {
    final room = Room(
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );

    await room.connect(wsUrl, token);
    room.addListener(_onRoomChanged);

    state = state.copyWith(
      connecting: false,
      connected: true,
      room: room,
      wsUrl: wsUrl,
      token: token,
      error: null,
      screenShareEnabled:
          room.localParticipant?.isScreenShareEnabled() ?? false,
    );

    final local = room.localParticipant;
    if (local != null) {
      if (!micEnabled) {
        await local.setMicrophoneEnabled(false);
      }
      if (!cameraEnabled) {
        await local.setCameraEnabled(false);
      }
      state = state.copyWith(screenShareEnabled: local.isScreenShareEnabled());
    }
    LoggingService.instance.logInfo(
      'livekit_connected',
      extras: {'ws_url': wsUrl},
    );
    unawaited(
      AnalyticsService.instance.logEvent(
        'livekit_connected',
        parameters: {'ws_url': wsUrl},
        crashlyticsBreadcrumb: true,
      ),
    );
  }

  Future<void> setScreenShareEnabled(bool enable) async {
    final room = state.room;
    final local = room?.localParticipant;
    if (local == null) {
      LoggingService.instance.logInfo(
        'livekit_screen_share_skipped',
        extras: {'enable': enable},
      );
      return;
    }

    try {
      await local.setScreenShareEnabled(enable);
      final isEnabled = local.isScreenShareEnabled();
      state = state.copyWith(screenShareEnabled: isEnabled, error: null);
      LoggingService.instance.logInfo(
        'livekit_screen_share_${isEnabled ? 'enabled' : 'disabled'}',
      );
      unawaited(
        AnalyticsService.instance.logEvent(
          'livekit_screen_share_${isEnabled ? 'enabled' : 'disabled'}',
          crashlyticsBreadcrumb: true,
        ),
      );
    } catch (error, stack) {
      LoggingService.instance.logError(
        'livekit_screen_share_error',
        error: error,
        stackTrace: stack,
      );
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> _cleanupRoom() async {
    final room = state.room;
    if (room != null) {
      room.removeListener(_onRoomChanged);
      try {
        await room.disconnect();
      } catch (_) {
        // swallow disconnect errors in teardown
      }
      await room.dispose();
    }
    state = state.copyWith(
      room: null,
      connected: false,
      screenShareEnabled: false,
    );
  }

  void _onRoomChanged() {
    final room = state.room;
    if (room == null) return;
    state = state.copyWith(
      connected: room.connectionState == ConnectionState.connected,
      screenShareEnabled:
          room.localParticipant?.isScreenShareEnabled() ??
          state.screenShareEnabled,
    );
    LoggingService.instance.logInfo(
      'livekit_room_state',
      extras: {
        'state': room.connectionState.name,
        'remote_participants': room.remoteParticipants.length,
      },
    );
    unawaited(
      AnalyticsService.instance.logEvent(
        'livekit_room_state',
        parameters: {
          'state': room.connectionState.name,
          'remote_participants': room.remoteParticipants.length,
        },
        crashlyticsBreadcrumb: true,
      ),
    );
  }
}

final liveSessionControllerProvider =
    AutoDisposeNotifierProvider<LiveSessionController, LiveSessionState>(
      LiveSessionController.new,
    );
