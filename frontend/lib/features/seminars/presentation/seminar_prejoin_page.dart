import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/home/application/livekit_controller.dart';
import 'package:aveli/features/seminars/presentation/seminar_route_args.dart';
import 'package:aveli/shared/utils/media_permissions.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class SeminarPreJoinPage extends ConsumerStatefulWidget {
  const SeminarPreJoinPage({required this.args, super.key});

  final SeminarPreJoinArgs args;

  @override
  ConsumerState<SeminarPreJoinPage> createState() => _SeminarPreJoinPageState();
}

class _SeminarPreJoinPageState extends ConsumerState<SeminarPreJoinPage> {
  final Hardware _hardware = Hardware.instance;

  List<MediaDevice> _videoDevices = const [];
  List<MediaDevice> _audioDevices = const [];
  MediaDevice? _selectedVideo;
  MediaDevice? _selectedAudio;
  LocalVideoTrack? _previewTrack;
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _loadingDevices = true;
  bool _starting = false;
  String? _previewError;
  bool _startWithScreenShare = false;

  void _handleCancel() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    context.goNamed(
      AppRoute.seminarDetail,
      pathParameters: {'id': widget.args.seminarId},
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveSessionControllerProvider.notifier).disconnect();
      _loadDevices();
    });
  }

  @override
  void dispose() {
    _disposePreviewTrack();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _loadingDevices = true;
      _previewError = null;
    });
    final permissionResult = await requestMediaPermissions(
      camera: true,
      microphone: true,
    );
    if (!permissionResult.granted) {
      if (mounted) {
        setState(() {
          _loadingDevices = false;
          _previewError = permissionResult.permanentlyDenied
              ? 'Ge appen åtkomst till kamera och mikrofon via systeminställningarna.'
              : 'Kamera- och mikrofonbehörighet krävs för att starta livesändningen.';
        });
      }
      return;
    }
    try {
      final videoInputs = await _hardware.videoInputs();
      final audioInputs = await _hardware.audioInputs();
      MediaDevice? defaultVideo = _hardware.selectedVideoInput;
      MediaDevice? defaultAudio = _hardware.selectedAudioInput;

      if (defaultVideo == null && videoInputs.isNotEmpty) {
        defaultVideo = videoInputs.first;
      }
      if (defaultAudio == null && audioInputs.isNotEmpty) {
        defaultAudio = audioInputs.first;
      }

      setState(() {
        _videoDevices = videoInputs;
        _audioDevices = audioInputs;
        _selectedVideo = defaultVideo;
        _selectedAudio = defaultAudio;
      });

      if (_cameraEnabled && _selectedVideo != null) {
        await _createPreviewTrack();
      }
    } catch (error) {
      setState(() {
        _previewError = 'Kunde inte läsa enheter: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingDevices = false;
        });
      }
    }
  }

  Future<void> _createPreviewTrack() async {
    await _disposePreviewTrack();
    if (!_cameraEnabled || _selectedVideo == null) {
      return;
    }
    final permissionResult = await requestMediaPermissions(
      camera: true,
      microphone: false,
    );
    if (!permissionResult.granted) {
      if (mounted) {
        setState(() {
          _previewTrack = null;
          _previewError = permissionResult.permanentlyDenied
              ? 'Öppna systeminställningarna för att ge kamerabehörighet.'
              : 'Kamerabehörighet krävs för att visa förhandsvisningen.';
        });
      }
      return;
    }
    try {
      final track = await LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(deviceId: _selectedVideo!.deviceId),
      );
      if (mounted) {
        setState(() {
          _previewTrack = track;
          _previewError = null;
        });
      } else {
        await track.stop();
        await track.dispose();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _previewTrack = null;
          _previewError =
              'Kunde inte starta kameraförhandsvisning: $error. Kontrollera rättigheter.';
        });
      }
    }
  }

  Future<void> _disposePreviewTrack() async {
    final track = _previewTrack;
    if (track != null) {
      await track.stop();
      await track.dispose();
      if (mounted) {
        setState(() {
          _previewTrack = null;
        });
      } else {
        _previewTrack = null;
      }
    }
  }

  Future<void> _startBroadcast() async {
    if (_starting) return;
    setState(() {
      _starting = true;
    });

    final permissionResult = await requestMediaPermissions(
      camera: _cameraEnabled,
      microphone: true,
    );
    if (!permissionResult.granted) {
      if (mounted) {
        setState(() => _starting = false);
        showMediaPermissionSnackbar(context, result: permissionResult);
      }
      return;
    }

    try {
      await _disposePreviewTrack();

      if (_selectedVideo != null) {
        _hardware.selectedVideoInput = _selectedVideo;
      }
      if (_selectedAudio != null) {
        _hardware.selectedAudioInput = _selectedAudio;
        try {
          await _hardware.selectAudioInput(_selectedAudio!);
        } catch (_) {
          // Some platforms do not support selecting audio input; ignore.
        }
      }

      final controller = ref.read(liveSessionControllerProvider.notifier);
      await controller.connectWithToken(
        wsUrl: widget.args.wsUrl,
        token: widget.args.token,
        micEnabled: _micEnabled,
        cameraEnabled: _cameraEnabled,
      );

      if (_startWithScreenShare && !lkPlatformIsMobile()) {
        await controller.setScreenShareEnabled(true);
      }

      if (!mounted) return;
      context.goNamed(
        AppRoute.seminarBroadcast,
        pathParameters: {'id': widget.args.seminarId},
        extra: SeminarBroadcastArgs(
          seminarId: widget.args.seminarId,
          session: widget.args.session,
          wsUrl: widget.args.wsUrl,
          token: widget.args.token,
          autoConnect: false,
          initialMicEnabled: _micEnabled,
          initialCameraEnabled: _cameraEnabled,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunde inte starta sändning: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _starting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleCancel();
      },
      child: AppScaffold(
        title: 'Förbered livesändning',
        showHomeAction: false,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: _loadingDevices
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PreviewSection(
                      track: _previewTrack,
                      cameraEnabled: _cameraEnabled,
                      error: _previewError,
                    ),
                    const SizedBox(height: 16),
                    _DeviceSelectors(
                      videoDevices: _videoDevices,
                      audioDevices: _audioDevices,
                      selectedVideo: _selectedVideo,
                      selectedAudio: _selectedAudio,
                      onVideoChanged: (device) async {
                        setState(() => _selectedVideo = device);
                        await _createPreviewTrack();
                      },
                      onAudioChanged: (device) {
                        setState(() => _selectedAudio = device);
                      },
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      value: _cameraEnabled,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Kamera'),
                      subtitle: const Text(
                        'Visa kameraflöde när sändningen startar',
                      ),
                      onChanged: (value) async {
                        setState(() => _cameraEnabled = value);
                        if (value) {
                          await _createPreviewTrack();
                        } else {
                          await _disposePreviewTrack();
                        }
                      },
                    ),
                    SwitchListTile(
                      value: _micEnabled,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mikrofon'),
                      subtitle: const Text('Dela ljud när sändningen startar'),
                      onChanged: (value) {
                        setState(() => _micEnabled = value);
                      },
                    ),
                    if (!lkPlatformIsMobile())
                      SwitchListTile(
                        value: _startWithScreenShare,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Starta med skärmdelning'),
                        subtitle: const Text('Tillgängligt på desktop/web'),
                        onChanged: (value) {
                          setState(() => _startWithScreenShare = value);
                        },
                      ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _starting ? null : _handleCancel,
                            child: const Text('Avbryt'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GradientButton.icon(
                            onPressed: _starting ? null : _startBroadcast,
                            icon: _starting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow_rounded),
                            label: const Text('Starta sändning'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({
    required this.track,
    required this.cameraEnabled,
    required this.error,
  });

  final LocalVideoTrack? track;
  final bool cameraEnabled;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: 220,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: cameraEnabled
              ? _buildCameraPreview()
              : const Center(child: Text('Kameran är avstängd')),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (error != null) {
      return Center(child: Text(error!, textAlign: TextAlign.center));
    }
    if (track == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: VideoTrackRenderer(
        track!,
        fit: VideoViewFit.cover,
        mirrorMode: VideoViewMirrorMode.auto,
      ),
    );
  }
}

class _DeviceSelectors extends StatelessWidget {
  const _DeviceSelectors({
    required this.videoDevices,
    required this.audioDevices,
    required this.selectedVideo,
    required this.selectedAudio,
    required this.onVideoChanged,
    required this.onAudioChanged,
  });

  final List<MediaDevice> videoDevices;
  final List<MediaDevice> audioDevices;
  final MediaDevice? selectedVideo;
  final MediaDevice? selectedAudio;
  final ValueChanged<MediaDevice?> onVideoChanged;
  final ValueChanged<MediaDevice?> onAudioChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enheter', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        DropdownButtonFormField<MediaDevice>(
          initialValue: videoDevices.contains(selectedVideo)
              ? selectedVideo
              : null,
          decoration: const InputDecoration(labelText: 'Kamera'),
          hint: videoDevices.isEmpty
              ? const Text('Ingen kamera hittades')
              : null,
          items: videoDevices
              .map(
                (device) => DropdownMenuItem<MediaDevice>(
                  value: device,
                  child: Text(
                    device.label.isNotEmpty
                        ? device.label
                        : 'Kamera (${device.deviceId})',
                  ),
                ),
              )
              .toList(),
          onChanged: videoDevices.isEmpty ? null : onVideoChanged,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<MediaDevice>(
          initialValue: audioDevices.contains(selectedAudio)
              ? selectedAudio
              : null,
          decoration: const InputDecoration(labelText: 'Mikrofon'),
          hint: audioDevices.isEmpty
              ? const Text('Ingen mikrofon hittades')
              : null,
          items: audioDevices
              .map(
                (device) => DropdownMenuItem<MediaDevice>(
                  value: device,
                  child: Text(
                    device.label.isNotEmpty
                        ? device.label
                        : 'Mikrofon (${device.deviceId})',
                  ),
                ),
              )
              .toList(),
          onChanged: audioDevices.isEmpty ? null : onAudioChanged,
        ),
      ],
    );
  }
}
