import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';
import 'package:aveli/features/studio/application/profile_media_controller.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/shared/widgets/hero_background.dart';

class StudioProfilePage extends ConsumerWidget {
  const StudioProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(teacherProfileMediaProvider);
    final isBusy = asyncState.isLoading;
    return AppScaffold(
      title: 'Media i Home-spelaren',
      extendBodyBehindAppBar: true,
      onBack: () => context.goNamed(AppRoute.home),
      contentPadding: const EdgeInsets.fromLTRB(16, 120, 16, 32),
      background: const HeroBackground(
        assetPath: 'images/bakgrund.png',
        opacity: 0.65,
      ),
      body: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          message: AppFailure.from(error).message,
          onRetry: () =>
              ref.read(teacherProfileMediaProvider.notifier).refresh(),
        ),
        data: (data) => _ProfileMediaBody(state: data, isBusy: isBusy),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isBusy
            ? null
            : () async {
                final state = asyncState.valueOrNull;
                if (state == null) return;
                await _ProfileMediaDialogs.showCreateDialog(
                  context,
                  ref,
                  state,
                );
              },
        icon: const Icon(Icons.add),
        label: const Text('Lägg till media'),
      ),
    );
  }
}

class _ProfileMediaBody extends ConsumerWidget {
  const _ProfileMediaBody({required this.state, required this.isBusy});

  final TeacherProfileMediaState state;
  final bool isBusy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items = state.sortedItems
        .where((item) => item.mediaKind == TeacherProfileMediaKind.lessonMedia)
        .toList(growable: false);
    final groupedItems = _groupByCourse(items);
    return SingleChildScrollView(
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        opacity: 0.10,
        sigmaX: 3,
        sigmaY: 3,
        borderColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Media i Home-spelaren',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Uppdatera',
                  onPressed: isBusy
                      ? null
                      : () =>
                            ref.read(teacherProfileMediaProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Här väljer du vilken av din media som får visas i Home-spelaren.\nEndast media du aktivt väljer här kan visas för elever.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            if (items.isEmpty)
              _EmptyState(
                onAdd: isBusy
                    ? null
                    : () => _ProfileMediaDialogs.showCreateDialog(
                        context,
                        ref,
                        state,
                      ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in groupedItems.entries) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          'Visa i Home-spelaren',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                    ),
                    for (var index = 0; index < entry.value.length; index++) ...[
                      _ProfileMediaRow(
                        item: entry.value[index],
                        disabled: isBusy,
                      ),
                      if (index != entry.value.length - 1)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                        ),
                    ],
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            const SizedBox(height: 6),
            Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            ),
            const SizedBox(height: 18),
            Text(
              'Tillgängligt innehåll',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            _AvailableContentList(
              title: 'Lektionsmedia',
              icon: Icons.play_circle_outline,
              color: theme.colorScheme.primary,
              emptyMessage:
                  'När du lägger till ljud, video eller bilder i dina lektioner visas de här.',
              entries: state.lessonSources
                  .map(
                    (item) => _AvailableContentEntry(
                      id: item.id,
                      subtitle: item.courseTitle ?? 'Okänd kurs',
                      title: item.lessonTitle ?? 'Namnlös lektion',
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 18),
            _AvailableContentList(
              title: 'Livesändningar',
              icon: Icons.mic_external_on_outlined,
              color: theme.colorScheme.secondary,
              emptyMessage:
                  'När du har spelat in ett liveseminarium visas det här.',
              entries: state.recordingSources
                  .map(
                    (item) => _AvailableContentEntry(
                      id: item.id,
                      subtitle: item.seminarTitle ?? 'Seminarium',
                      title: item.assetUrl,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  static Map<String, List<TeacherProfileMediaItem>> _groupByCourse(
    List<TeacherProfileMediaItem> items,
  ) {
    final byCourse = <String, List<TeacherProfileMediaItem>>{};
    final other = <TeacherProfileMediaItem>[];

    for (final item in items) {
      final courseTitle = item.source.lessonMedia?.courseTitle?.trim();
      if (courseTitle != null && courseTitle.isNotEmpty) {
        byCourse.putIfAbsent(courseTitle, () => []).add(item);
      } else {
        other.add(item);
      }
    }

    final sortedCourseTitles = byCourse.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final grouped = <String, List<TeacherProfileMediaItem>>{
      for (final title in sortedCourseTitles) title: byCourse[title]!,
    };
    if (other.isNotEmpty) {
      grouped['Allmän media'] = other;
    }
    return grouped;
  }
}

class _ProfileMediaRow extends ConsumerWidget {
  const _ProfileMediaRow({required this.item, required this.disabled});

  final TeacherProfileMediaItem item;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(teacherProfileMediaProvider.notifier);
    final theme = Theme.of(context);
    final formatLabel = _formatLabelFor(item);
    final duration = item.source.lessonMedia?.durationSeconds;
    final durationLabel = duration != null ? _durationLabel(duration) : null;
    final metadata = <String>[
      if (formatLabel != null) formatLabel,
      if (durationLabel != null) durationLabel,
    ].join(' • ');
    final icon = _iconFor(item);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      opacity: item.enabledForHomePlayer ? 1 : 0.62,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _titleFor(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '($metadata)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(
              value: item.enabledForHomePlayer,
              onChanged: disabled
                  ? null
                  : (value) async {
                      try {
                        await controller.toggleHomePlayer(item.id, value);
                      } catch (error) {
                        if (!context.mounted) return;
                        _showErrorSnackBar(context, error);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  static String _titleFor(TeacherProfileMediaItem item) {
    if ((item.title ?? '').trim().isNotEmpty) return item.title!.trim();
    switch (item.mediaKind) {
      case TeacherProfileMediaKind.lessonMedia:
        return item.source.lessonMedia?.lessonTitle ?? 'Lektionsmedia';
      case TeacherProfileMediaKind.seminarRecording:
        return item.source.seminarRecording?.seminarTitle ?? 'Livesändning';
      case TeacherProfileMediaKind.external:
        return item.externalUrl ?? 'Extern länk';
    }
  }

  static String? _formatLabelFor(TeacherProfileMediaItem item) {
    final lesson = item.source.lessonMedia;
    if (lesson == null) return null;
    final contentType = (lesson.contentType ?? '').toLowerCase();
    if (contentType.contains('wav')) return 'wav';
    if (contentType.contains('mpeg') || contentType.contains('mp3')) {
      return 'mp3';
    }

    final path = (lesson.storagePath ?? '').toLowerCase();
    if (path.endsWith('.wav')) return 'wav';
    if (path.endsWith('.mp3')) return 'mp3';

    return null;
  }

  static String _durationLabel(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = safeSeconds ~/ 60;
    final remaining = safeSeconds % 60;
    return '$minutes:${remaining.toString().padLeft(2, '0')}';
  }

  static IconData _iconFor(TeacherProfileMediaItem item) {
    final lesson = item.source.lessonMedia;
    final contentType = (lesson?.contentType ?? '').toLowerCase();
    if (contentType.startsWith('audio/')) return Icons.headphones_rounded;
    if (contentType.startsWith('video/')) return Icons.videocam_outlined;
    if (contentType.startsWith('image/')) return Icons.image_outlined;
    if (contentType.contains('pdf')) return Icons.picture_as_pdf_outlined;

    final path = (lesson?.storagePath ?? '').toLowerCase();
    if (path.endsWith('.wav') || path.endsWith('.mp3')) {
      return Icons.headphones_rounded;
    }
    return Icons.insert_drive_file_outlined;
  }
}

class _AvailableContentEntry {
  const _AvailableContentEntry({
    required this.id,
    required this.title,
    required this.subtitle,
  });

  final String id;
  final String title;
  final String subtitle;
}

class _AvailableContentList extends StatelessWidget {
  const _AvailableContentList({
    required this.title,
    required this.icon,
    required this.color,
    required this.emptyMessage,
    required this.entries,
  });

  final String title;
  final IconData icon;
  final Color color;
  final String emptyMessage;
  final List<_AvailableContentEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          Text(
            emptyMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Column(
            children: [
              for (final entry in entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.14),
                    foregroundColor: color,
                    child: Text(_initial(entry.title)),
                  ),
                  title: Text(entry.title),
                  subtitle: Text(
                    entry.subtitle,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  String _initial(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.isEmpty) return '•';
    final rune = trimmed.runes.first;
    return String.fromCharCode(rune).toUpperCase();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(
          Icons.collections_bookmark_outlined,
          size: 64,
          color: theme.colorScheme.primary.withValues(alpha: 0.7),
        ),
        const SizedBox(height: 12),
        Text(
          'Ingen media ännu.',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Lägg till media från dina lektioner så att du kan välja vad som får visas i Home-spelaren.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        GradientButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Lägg till media'),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Försök igen'),
          ),
        ],
      ),
    );
  }
}

class _ProfileMediaDialogs {
  static Future<void> showCreateDialog(
    BuildContext context,
    WidgetRef ref,
    TeacherProfileMediaState state,
  ) async {
    final controller = ref.read(teacherProfileMediaProvider.notifier);
    final lessonSources = state.lessonSources
        .where((item) => item.kind.toLowerCase() == 'audio')
        .toList(growable: false);
    if (lessonSources.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lägg till media'),
          content: const Text(
            'Inget ljud hittades i dina lektioner ännu. Lägg till ljud i en lektion först.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Stäng'),
            ),
          ],
        ),
      );
      return;
    }
    String? selectedLessonId = lessonSources.first.id;
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    try {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Lägg till ljud från en lektion'),
                content: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          // ignore: deprecated_member_use
                          value: selectedLessonId,
                          decoration: const InputDecoration(
                            labelText: 'Välj lektion',
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Välj en lektion'
                              : null,
                          items: lessonSources
                              .map(
                                (lesson) => DropdownMenuItem(
                                  value: lesson.id,
                                  child: Text(
                                    '${lesson.courseTitle ?? 'Kurs'} · ${lesson.lessonTitle ?? 'Lektion'}',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => selectedLessonId = value);
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: titleController,
                          decoration: const InputDecoration(
                            labelText: 'Titel (valfritt)',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Beskrivning (valfri)',
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Avbryt'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      try {
                        await controller.createItem(
                          kind: TeacherProfileMediaKind.lessonMedia,
                          mediaId: selectedLessonId,
                          title: titleController.text.trim().isEmpty
                              ? null
                              : titleController.text.trim(),
                          description: descriptionController.text.trim().isEmpty
                              ? null
                              : descriptionController.text.trim(),
                          isPublished: false,
                        );
                        if (context.mounted) Navigator.of(context).pop();
                      } catch (error) {
                        if (!context.mounted) return;
                        _showErrorSnackBar(context, error);
                      }
                    },
                    child: const Text('Lägg till'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      titleController.dispose();
      descriptionController.dispose();
    }
  }
}

void _showErrorSnackBar(BuildContext context, Object error) {
  final failure = AppFailure.from(error);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(failure.message),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}
