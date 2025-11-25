import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/features/seminars/application/seminar_providers.dart';
import 'package:wisdom/data/models/seminar.dart';
import 'package:wisdom/data/repositories/seminar_repository.dart';
import 'package:wisdom/features/home/application/livekit_controller.dart';
import 'package:wisdom/features/seminars/presentation/seminar_route_args.dart';
import 'package:wisdom/shared/utils/error_messages.dart';
import 'package:wisdom/shared/widgets/app_scaffold.dart';
import 'package:wisdom/shared/widgets/gradient_button.dart';

import 'seminar_background.dart';

class SeminarDetailPage extends ConsumerWidget {
  const SeminarDetailPage({required this.seminarId, super.key});

  final String seminarId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(seminarDetailProvider(seminarId));

    return AppScaffold(
      title: 'Seminarium',
      background: const SeminarBackground(),
      extendBodyBehindAppBar: true,
      transparentAppBar: true,
      logoSize: 0,
      contentPadding: const EdgeInsets.fromLTRB(
        16,
        kToolbarHeight + 40,
        16,
        32,
      ),
      body: detailAsync.when(
        data: (detail) => _DetailBody(detail: detail),
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
                  onPressed: () =>
                      ref.invalidate(seminarDetailProvider(seminarId)),
                  child: const Text('Försök igen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.detail});

  final SeminarDetail detail;

  Seminar get seminar => detail.seminar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repository = ref.watch(seminarRepositoryProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(seminarDetailProvider(seminar.id).future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(seminar.title, style: theme.textTheme.headlineSmall),
                  if (seminar.description != null &&
                      seminar.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(seminar.description!),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(
                        label: Text(seminar.status.name.toUpperCase()),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (seminar.scheduledAt != null)
                        Chip(
                          label: Text(
                            'Start ${seminar.scheduledAt!.toLocal()}',
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (seminar.durationMinutes != null)
                        Chip(
                          label: Text('${seminar.durationMinutes} min'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (seminar.status == SeminarStatus.draft ||
                          seminar.status == SeminarStatus.canceled)
                        GradientButton(
                          onPressed: () async {
                            await repository.publishSeminar(seminar.id);
                            ref.invalidate(hostSeminarsProvider);
                            ref.invalidate(seminarDetailProvider(seminar.id));
                          },
                          child: const Text('Publicera'),
                        ),
                      if (seminar.status == SeminarStatus.scheduled) ...[
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () async {
                            await repository.cancelSeminar(seminar.id);
                            ref.invalidate(hostSeminarsProvider);
                            ref.invalidate(seminarDetailProvider(seminar.id));
                          },
                          child: const Text('Avbryt'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SessionsSection(detail: detail),
          const SizedBox(height: 16),
          _AttendeesSection(detail: detail),
          const SizedBox(height: 16),
          _RecordingsSection(detail: detail),
        ],
      ),
    );
  }
}

class _SessionsSection extends ConsumerWidget {
  const _SessionsSection({required this.detail});

  final SeminarDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(seminarRepositoryProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sessioner',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                GradientButton.icon(
                  onPressed: () async {
                    try {
                      final result = await repository.startSession(
                        detail.seminar.id,
                      );
                      ref.invalidate(seminarDetailProvider(detail.seminar.id));
                      if (!context.mounted) return;
                      context.goNamed(
                        AppRoute.seminarPreJoin,
                        pathParameters: {'id': detail.seminar.id},
                        extra: SeminarPreJoinArgs(
                          seminarId: detail.seminar.id,
                          session: result.session,
                          wsUrl: result.wsUrl,
                          token: result.token,
                        ),
                      );
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Kunde inte starta session: ${friendlyHttpError(error)}',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Starta sändning'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (detail.sessions.isEmpty)
              const Text('Inga sessioner ännu.')
            else
              Column(
                children: detail.sessions.map((session) {
                  return ListTile(
                    leading: Icon(
                      session.status == SeminarSessionStatus.live
                          ? Icons.circle_outlined
                          : Icons.play_circle_outline,
                    ),
                    title: Text('Session ${session.status.name}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (session.startedAt != null)
                          Text('Start: ${session.startedAt!.toLocal()}'),
                        if (session.endedAt != null)
                          Text('Slut: ${session.endedAt!.toLocal()}'),
                      ],
                    ),
                    trailing: session.status == SeminarSessionStatus.live
                        ? TextButton(
                            onPressed: () async {
                              try {
                                await repository.endSession(
                                  detail.seminar.id,
                                  session.id,
                                );
                                await ref
                                    .read(
                                      liveSessionControllerProvider.notifier,
                                    )
                                    .disconnect();
                                if (!context.mounted) return;
                                ref.invalidate(
                                  seminarDetailProvider(detail.seminar.id),
                                );
                              } catch (error) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Kunde inte avsluta: $error'),
                                  ),
                                );
                              }
                            },
                            child: const Text('Avsluta'),
                          )
                        : null,
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttendeesSection extends ConsumerWidget {
  const _AttendeesSection({required this.detail});

  final SeminarDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Deltagare',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                GradientButton.icon(
                  onPressed: () => _grantAccess(context, ref),
                  icon: const Icon(Icons.person_add_alt_rounded),
                  label: const Text('Ge behörighet'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (detail.attendees.isEmpty)
              const Text('Inga anmälda deltagare ännu.')
            else
              Column(
                children: detail.attendees.map((attendee) {
                  final title = attendee.displayName?.isNotEmpty == true
                      ? attendee.displayName!
                      : attendee.email?.isNotEmpty == true
                      ? attendee.email!
                      : attendee.userId;
                  final email = attendee.email;
                  return ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (email != null && email.isNotEmpty)
                          Text(email)
                        else
                          const Text('Ingen registrerad e-post'),
                        Text('Status: ${attendee.inviteStatus}'),
                        if (attendee.hostCourseTitles.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: attendee.hostCourseTitles
                                  .map(
                                    (courseTitle) => Chip(
                                      label: Text(
                                        courseTitle,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Ta bort behörighet',
                      onPressed: () =>
                          _revokeAccess(context, ref, attendee.userId),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _grantAccess(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    var autoAccept = true;
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Ge behörighet'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Användar-ID (UUID)',
                        helperText: 'Behörighet ges via användarens ID.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Markera som accepterad direkt'),
                      value: autoAccept,
                      onChanged: (value) {
                        setState(() {
                          autoAccept = value;
                        });
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Avbryt'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Spara'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (confirm != true) {
        return;
      }

      final userId = controller.text.trim();
      if (userId.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ange ett användar-ID.')));
        return;
      }

      try {
        await ref
            .read(seminarRepositoryProvider)
            .grantSeminarAccess(
              seminarId: detail.seminar.id,
              userId: userId,
              inviteStatus: autoAccept ? 'accepted' : 'pending',
            );
        ref.invalidate(seminarDetailProvider(detail.seminar.id));
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Behörighet tilldelad.')));
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunde inte ge behörighet: $error')),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _revokeAccess(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ta bort behörighet'),
          content: Text(
            'Vill du ta bort behörigheten för användare:\n$userId?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Ta bort'),
            ),
          ],
        );
      },
    );
    if (confirm != true) {
      return;
    }

    try {
      await ref
          .read(seminarRepositoryProvider)
          .revokeSeminarAccess(seminarId: detail.seminar.id, userId: userId);
      ref.invalidate(seminarDetailProvider(detail.seminar.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Behörigheten togs bort.')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte ta bort behörighet: $error')),
      );
    }
  }
}

class _RecordingsSection extends StatelessWidget {
  const _RecordingsSection({required this.detail});

  final SeminarDetail detail;

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
            if (detail.recordings.isEmpty)
              const Text('Inga inspelningar tillgängliga.')
            else
              Column(
                children: detail.recordings.map((recording) {
                  return ListTile(
                    leading: const Icon(Icons.video_library_outlined),
                    title: Text(recording.assetUrl),
                    subtitle: Text('Status: ${recording.status}'),
                    trailing: recording.published
                        ? const Icon(Icons.visibility)
                        : const Icon(Icons.visibility_off),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
