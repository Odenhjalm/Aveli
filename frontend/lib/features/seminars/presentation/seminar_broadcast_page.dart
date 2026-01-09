import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/repositories/seminar_repository.dart';
import 'package:aveli/features/seminars/application/seminar_providers.dart';
import 'package:aveli/features/home/application/livekit_controller.dart';
import 'package:aveli/features/seminars/presentation/seminar_route_args.dart';
import 'package:aveli/shared/utils/media_permissions.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/shared/widgets/safe_background.dart';

enum _EndSessionDecision { saveRecording, endOnly }

class SeminarBroadcastPage extends ConsumerStatefulWidget {
  const SeminarBroadcastPage({required this.args, super.key});

  final SeminarBroadcastArgs args;

  @override
  ConsumerState<SeminarBroadcastPage> createState() =>
      _SeminarBroadcastPageState();
}

class _SeminarBroadcastPageState extends ConsumerState<SeminarBroadcastPage> {
  late bool _micEnabled;
  late bool _cameraEnabled;
  bool _ending = false;

  VideoTrack? _selectLocalVideoTrack(Room? room) {
    final local = room?.localParticipant;
    if (local == null) {
      return null;
    }
    for (final publication in local.videoTrackPublications) {
      if (publication.source == TrackSource.camera &&
          publication.track != null) {
        return publication.track;
      }
    }
    for (final publication in local.videoTrackPublications) {
      final track = publication.track;
      if (track != null) {
        return track;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _micEnabled = widget.args.initialMicEnabled;
    _cameraEnabled = widget.args.initialCameraEnabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.args.autoConnect) {
        Future<void>(() async {
          if (!mounted) return;
          final permissionResult = await requestMediaPermissions(
            camera: _cameraEnabled,
            microphone: true,
          );
          if (!permissionResult.granted) {
            if (mounted) {
              showMediaPermissionSnackbar(context, result: permissionResult);
            }
            return;
          }
          await ref
              .read(liveSessionControllerProvider.notifier)
              .connectWithToken(
                wsUrl: widget.args.wsUrl,
                token: widget.args.token,
                micEnabled: _micEnabled,
                cameraEnabled: _cameraEnabled,
              );
        });
      }
    });
  }

  @override
  void dispose() {
    ref.read(liveSessionControllerProvider.notifier).disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveSessionControllerProvider);
    final repository = ref.watch(seminarRepositoryProvider);
    final backgroundImage =
        AppImages.background; // använd bundlad resurs för förladdning
    ref.listen<LiveSessionState>(liveSessionControllerProvider, (
      previous,
      next,
    ) {
      final error = next.error;
      if (error != null && error != previous?.error && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('LiveKit: $error')));
      }
    });

    final room = state.room;
    if (room != null) {
      final local = room.localParticipant;
      if (local != null) {
        final mic = local.isMicrophoneEnabled();
        final camera = local.isCameraEnabled();
        if (mic != _micEnabled || camera != _cameraEnabled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _micEnabled = mic;
                _cameraEnabled = camera;
              });
            }
          });
        }
      }
    }

    final canShareScreen = !lkPlatformIsMobile();
    final localVideoTrack = _selectLocalVideoTrack(room);
    final controlsEnabled = state.connected && !_ending;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Livesändning'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: _ending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.stop_circle_outlined),
            tooltip: 'Avsluta sändning',
            onPressed: state.connected && !_ending
                ? () => _handleEndSession(repository)
                : null,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: SafeBackground(
              image: backgroundImage,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x33000000), Colors.transparent],
                    stops: [0.0, 0.35],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.args.session.status.name.toUpperCase(),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Room: ${widget.args.session.livekitRoom ?? '—'}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              state.connected
                                  ? 'Status: Ansluten'
                                  : state.connecting
                                  ? 'Status: Ansluter…'
                                  : 'Status: Frånkopplad',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Skärmdelning: ${state.screenShareEnabled ? 'Aktiv' : 'Av'}',
                            ),
                            if (state.error != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                state.error!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      fit: FlexFit.loose,
                      child: _BroadcastPreview(
                        track: localVideoTrack,
                        connected: state.connected,
                        cameraEnabled: _cameraEnabled,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: GradientButton.icon(
                            onPressed: controlsEnabled
                                ? () async {
                                    final currentRoom = state.room;
                                    if (currentRoom != null) {
                                      final local =
                                          currentRoom.localParticipant;
                                      if (local != null) {
                                        await local.setMicrophoneEnabled(
                                          !_micEnabled,
                                        );
                                        final updated = local
                                            .isMicrophoneEnabled();
                                        if (mounted) {
                                          setState(() => _micEnabled = updated);
                                        }
                                      }
                                    }
                                  }
                                : null,
                            icon: Icon(
                              _micEnabled
                                  ? Icons.mic_none_rounded
                                  : Icons.mic_off_rounded,
                            ),
                            label: Text(_micEnabled ? 'Mute' : 'Unmute'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: controlsEnabled
                                ? () async {
                                    final currentRoom = state.room;
                                    if (currentRoom != null) {
                                      final local =
                                          currentRoom.localParticipant;
                                      if (local != null) {
                                        await local.setCameraEnabled(
                                          !_cameraEnabled,
                                        );
                                        final updated = local.isCameraEnabled();
                                        if (mounted) {
                                          setState(
                                            () => _cameraEnabled = updated,
                                          );
                                        }
                                      }
                                    }
                                  }
                                : null,
                            icon: Icon(
                              _cameraEnabled
                                  ? Icons.videocam_outlined
                                  : Icons.videocam_off_outlined,
                            ),
                            label: Text(
                              _cameraEnabled ? 'Stäng kamera' : 'Starta kamera',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: !canShareScreen || !controlsEnabled
                          ? null
                          : () => ref
                                .read(liveSessionControllerProvider.notifier)
                                .setScreenShareEnabled(
                                  !state.screenShareEnabled,
                                ),
                      icon: Icon(
                        state.screenShareEnabled
                            ? Icons.stop_screen_share_outlined
                            : Icons.screen_share_outlined,
                      ),
                      label: Text(
                        state.screenShareEnabled
                            ? 'Stoppa skärmdelning'
                            : 'Dela skärm',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Deltagare',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: state.room == null
                          ? const Text('Ingen aktiv anslutning')
                          : Builder(
                              builder: (context) {
                                final room = state.room!;
                                return ListView(
                                  children: [
                                    ListTile(
                                      leading: const Icon(
                                        Icons.person_pin_circle,
                                      ),
                                      title: const Text('Du (värd)'),
                                      subtitle: Text(
                                        widget.args.session.livekitSid ?? '',
                                      ),
                                    ),
                                    for (final participant
                                        in room.remoteParticipants.values)
                                      ListTile(
                                        leading: const Icon(
                                          Icons.person_outline,
                                        ),
                                        title: Text(participant.identity),
                                        subtitle: Text(participant.sid),
                                      ),
                                  ],
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleEndSession(SeminarRepository repository) async {
    if (_ending) return;
    final decision = await _showEndSessionSheet();
    if (decision == null) {
      return;
    }
    setState(() => _ending = true);
    try {
      bool reserved = false;
      if (decision == _EndSessionDecision.saveRecording) {
        try {
          await repository.reserveRecording(
            widget.args.seminarId,
            sessionId: widget.args.session.id,
          );
          reserved = true;
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Kunde inte skapa lagringsplats: ${error.toString()}',
                ),
              ),
            );
          }
        }
      }

      await repository.endSession(
        widget.args.seminarId,
        widget.args.session.id,
        reason: decision == _EndSessionDecision.saveRecording ? 'save' : 'end',
      );

      ref.invalidate(seminarDetailProvider(widget.args.seminarId));
      ref.invalidate(hostSeminarsProvider);
      ref.read(liveSessionControllerProvider.notifier).disconnect();

      if (mounted && reserved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plats för inspelning skapad.')),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      if (mounted) {
        _navigateAfterEnd();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunde inte avsluta sändning: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _ending = false);
      }
    }
  }

  Future<_EndSessionDecision?> _showEndSessionSheet() {
    return showModalBottomSheet<_EndSessionDecision>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Avsluta livesändning',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'Vill du skapa en plats för inspelningen innan du stänger sändningen? '
                  'Filen kan sparas eller laddas upp senare.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                GradientButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(_EndSessionDecision.saveRecording),
                  child: const Text('Spara plats och avsluta'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_EndSessionDecision.endOnly),
                  child: const Text('Avsluta utan att spara'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Avbryt'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _navigateAfterEnd() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.goNamed(
        AppRoute.seminarDetail,
        pathParameters: {'id': widget.args.seminarId},
      );
    }
  }
}

class _BroadcastPreview extends StatelessWidget {
  const _BroadcastPreview({
    required this.track,
    required this.connected,
    required this.cameraEnabled,
  });

  final VideoTrack? track;
  final bool connected;
  final bool cameraEnabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Colors.black87),
              child: !connected
                  ? const Center(
                      child: Text(
                        'Ansluter...',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : !cameraEnabled
                  ? const Center(
                      child: Text(
                        'Kameran är avstängd',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : track == null
                  ? const Center(child: CircularProgressIndicator())
                  : VideoTrackRenderer(
                      track!,
                      fit: VideoViewFit.cover,
                      mirrorMode: VideoViewMirrorMode.mirror,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
