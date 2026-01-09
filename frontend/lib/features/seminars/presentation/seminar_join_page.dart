import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:aveli/data/models/seminar.dart';
import 'package:aveli/features/seminars/application/seminar_providers.dart';
import 'package:aveli/data/repositories/seminar_repository.dart';
import 'package:aveli/features/home/application/livekit_controller.dart';
import 'package:aveli/shared/utils/error_messages.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/shared/widgets/safe_background.dart';

class SeminarJoinPage extends ConsumerStatefulWidget {
  const SeminarJoinPage({required this.seminarId, super.key});

  final String seminarId;

  @override
  ConsumerState<SeminarJoinPage> createState() => _SeminarJoinPageState();
}

class _SeminarJoinPageState extends ConsumerState<SeminarJoinPage> {
  bool _joining = false;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(
      publicSeminarDetailProvider(widget.seminarId),
    );
    final sessionState = ref.watch(liveSessionControllerProvider);
    final assets = ref.watch(backendAssetResolverProvider);
    final backgroundImage =
        AppImages.background; // Bundlad bakgrund kräver ingen auth-token.
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

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Delta i liveseminarium'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
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
              child: detailAsync.when(
                data: (detail) {
                  _schedulePoll(detail, ref);
                  final seminar = detail.seminar;
                  SeminarSession? liveSession;
                  for (final session in detail.sessions) {
                    if (session.status == SeminarSessionStatus.live) {
                      liveSession = session;
                      break;
                    }
                  }
                  liveSession ??= detail.sessions.isNotEmpty
                      ? detail.sessions.first
                      : null;
                  final String sessionStatusLabel = liveSession != null
                      ? liveSession.status.name.toUpperCase()
                      : 'Ingen session';
                  final DateTime? sessionStartedAt = liveSession?.startedAt;
                  final bool canJoin =
                      liveSession != null &&
                      liveSession.status == SeminarSessionStatus.live;

                  return Padding(
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
                                  seminar.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                if (seminar.description != null) ...[
                                  const SizedBox(height: 8),
                                  Text(seminar.description!),
                                ],
                                const SizedBox(height: 12),
                                Text('Status: ${seminar.status.name}'),
                                if (seminar.scheduledAt != null)
                                  Text(
                                    'Start: ${seminar.scheduledAt!.toLocal()}',
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Session',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text('Status: $sessionStatusLabel'),
                                if (sessionStartedAt != null)
                                  Text(
                                    'Startade: ${sessionStartedAt.toLocal()}',
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: GradientButton.icon(
                                onPressed:
                                    _joining ||
                                        sessionState.connecting ||
                                        !canJoin
                                    ? null
                                    : () => _joinSeminar(ref, seminar),
                                icon: _joining || sessionState.connecting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.play_arrow_rounded),
                                label: const Text('Anslut'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: sessionState.connected
                                    ? ref
                                          .read(
                                            liveSessionControllerProvider
                                                .notifier,
                                          )
                                          .disconnect
                                    : null,
                                icon: const Icon(Icons.stop),
                                label: const Text('Koppla från'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (!canJoin)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Vi uppdaterar listan automatiskt. Knappen blir aktiv när sändningen går live.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        Expanded(
                          child: _ParticipantView(
                            state: sessionState,
                            seminar: seminar,
                            recordings: detail.recordings,
                          ),
                        ),
                        if (seminar.status == SeminarStatus.ended &&
                            detail.recordings.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _RecordingCard(recordings: detail.recordings),
                        ],
                      ],
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Kunde inte läsa seminarium: $error'),
                        const SizedBox(height: 12),
                        GradientButton(
                          onPressed: () => ref.invalidate(
                            publicSeminarDetailProvider(widget.seminarId),
                          ),
                          child: const Text('Försök igen'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _schedulePoll(SeminarDetail detail, WidgetRef ref) {
    _pollTimer?.cancel();
    final hasLive = detail.sessions.any(
      (session) => session.status == SeminarSessionStatus.live,
    );
    if (!hasLive && detail.seminar.status != SeminarStatus.ended) {
      _pollTimer = Timer(const Duration(seconds: 20), () {
        if (mounted) {
          ref.invalidate(publicSeminarDetailProvider(widget.seminarId));
        }
      });
    }
  }

  Future<void> _joinSeminar(WidgetRef ref, Seminar seminar) async {
    setState(() => _joining = true);
    try {
      final repository = ref.read(seminarRepositoryProvider);
      await repository.registerForSeminar(widget.seminarId);
      if (!mounted) return;

      final result = await showModalBottomSheet<_PreJoinResult>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _ParticipantPreJoinSheet(seminar: seminar),
      );

      if (result == null || !result.confirmed) {
        return;
      }

      await ref
          .read(liveSessionControllerProvider.notifier)
          .connect(widget.seminarId, micEnabled: false, cameraEnabled: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kunde inte ansluta: ${friendlyHttpError(error)}'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _joining = false);
      }
    }
  }
}

class _ParticipantView extends StatelessWidget {
  const _ParticipantView({
    required this.state,
    required this.seminar,
    required this.recordings,
  });

  final LiveSessionState state;
  final Seminar seminar;
  final List<SeminarRecording> recordings;

  @override
  Widget build(BuildContext context) {
    final room = state.room;
    if (state.connected && room != null) {
      final participants = room.remoteParticipants.values;
      if (participants.isNotEmpty) {
        return ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.person_pin_circle),
              title: const Text('Du'),
              subtitle: Text(room.localParticipant?.identity ?? ''),
            ),
            for (final participant in participants)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(participant.identity),
                subtitle: Text(participant.sid),
              ),
          ],
        );
      }
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 42),
          SizedBox(height: 12),
          Text('Inga andra deltagare är anslutna ännu.'),
        ],
      );
    }

    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.person_search, size: 42),
        SizedBox(height: 12),
        Text('Väntar på att värden ska starta sändningen...'),
      ],
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.recordings});

  final List<SeminarRecording> recordings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Inspelningar',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final recording in recordings)
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text('Inspelning ${recording.createdAt.toLocal()}'),
                onTap: () => _openRecording(recording.assetUrl, context),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRecording(String url, BuildContext context) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ogiltig inspelningslänk.')));
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kunde inte öppna inspelningen.')),
        );
      }
    }
  }
}

class _PreJoinResult {
  const _PreJoinResult({
    required this.confirmed,
    required this.micEnabled,
    required this.cameraEnabled,
  });

  final bool confirmed;
  final bool micEnabled;
  final bool cameraEnabled;
}

class _ParticipantPreJoinSheet extends StatelessWidget {
  const _ParticipantPreJoinSheet({required this.seminar});

  final Seminar seminar;

  void _close(BuildContext context, {required bool confirmed}) {
    Navigator.of(context).pop(
      _PreJoinResult(
        confirmed: confirmed,
        micEnabled: false,
        cameraEnabled: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gå med i ${seminar.title}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Du ansluter som åhörare. Kamera och mikrofon är avstängda under hela sändningen, '
              'men du syns i deltagarlistan.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Vill du delta aktivt kontaktar du läraren, annars kan du luta dig tillbaka och lyssna.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _close(context, confirmed: false),
                    child: const Text('Avbryt'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GradientButton(
                    onPressed: () => _close(context, confirmed: true),
                    child: const Text('Gå med'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
