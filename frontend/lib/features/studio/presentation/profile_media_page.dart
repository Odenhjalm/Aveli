import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
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
      title: 'Min profil',
      extendBodyBehindAppBar: true,
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
    final items = state.sortedItems;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Media på din profil',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Uppdatera',
                      onPressed: isBusy
                          ? null
                          : () => ref
                                .read(teacherProfileMediaProvider.notifier)
                                .refresh(),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Välj vilka lektioner, inspelningar eller externa länkar som ska visas på din offentliga profil. Använd pilarna för att justera ordning och växla publicering när du vill dölja ett kort.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
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
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: _ProfileMediaTile(
                            index: i,
                            total: items.length,
                            item: items[i],
                            disabled: isBusy,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tillgängligt innehåll',
                  style: theme.textTheme.titleLarge?.copyWith(
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
                const SizedBox(height: 20),
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
        ],
      ),
    );
  }
}

class _ProfileMediaTile extends ConsumerWidget {
  const _ProfileMediaTile({
    required this.index,
    required this.total,
    required this.item,
    required this.disabled,
  });

  final int index;
  final int total;
  final TeacherProfileMediaItem item;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(teacherProfileMediaProvider.notifier);
    final theme = Theme.of(context);
    final subtitle = _subtitleFor(item);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titleFor(item),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (subtitle != null) ...[
                        Text(subtitle, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        'Position ${index + 1} av $total · ${_kindLabel(item.mediaKind)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Flytta upp',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: disabled || index == 0
                          ? null
                          : () => controller.reorder(index, index - 1),
                    ),
                    IconButton(
                      tooltip: 'Flytta ned',
                      icon: const Icon(Icons.arrow_downward),
                      onPressed: disabled || index >= total - 1
                          ? null
                          : () => controller.reorder(index, index + 1),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Switch.adaptive(
                    value: item.isPublished,
                    onChanged: disabled
                        ? null
                        : (value) async {
                            try {
                              await controller.togglePublish(item.id, value);
                            } catch (error) {
                              if (!context.mounted) return;
                              _showErrorSnackBar(context, error);
                            }
                          },
                  ),
                  IconButton(
                    tooltip: 'Redigera',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: disabled
                        ? null
                        : () => _ProfileMediaDialogs.showEditDialog(
                            context,
                            ref,
                            item,
                          ),
                  ),
                  IconButton(
                    tooltip: 'Ta bort',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: disabled
                        ? null
                        : () => _ProfileMediaDialogs.confirmDelete(
                            context,
                            ref,
                            item,
                          ),
                  ),
                ],
              ),
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

  static String? _subtitleFor(TeacherProfileMediaItem item) {
    switch (item.mediaKind) {
      case TeacherProfileMediaKind.lessonMedia:
        final course = item.source.lessonMedia?.courseTitle;
        if (course == null) return null;
        return 'Från kursen $course';
      case TeacherProfileMediaKind.seminarRecording:
        return 'Inspelning · ${item.source.seminarRecording?.status ?? 'okänd status'}';
      case TeacherProfileMediaKind.external:
        return item.description;
    }
  }

  static String _kindLabel(TeacherProfileMediaKind kind) {
    switch (kind) {
      case TeacherProfileMediaKind.lessonMedia:
        return 'Lektion';
      case TeacherProfileMediaKind.seminarRecording:
        return 'Livesändning';
      case TeacherProfileMediaKind.external:
        return 'Extern länk';
    }
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
          'Inga media är kopplade ännu.',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Välj lektioner eller inspelningar för att bygga en attraktiv profil.',
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
    final lessonSources = state.lessonSources;
    final recordingSources = state.recordingSources;
    TeacherProfileMediaKind kind = lessonSources.isNotEmpty
        ? TeacherProfileMediaKind.lessonMedia
        : recordingSources.isNotEmpty
        ? TeacherProfileMediaKind.seminarRecording
        : TeacherProfileMediaKind.external;
    String? selectedLessonId = lessonSources.isNotEmpty
        ? lessonSources.first.id
        : null;
    String? selectedRecordingId = recordingSources.isNotEmpty
        ? recordingSources.first.id
        : null;
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final urlController = TextEditingController();
    bool isPublished = true;
    final formKey = GlobalKey<FormState>();

    try {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Lägg till media'),
                content: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<TeacherProfileMediaKind>(
                          // ignore: deprecated_member_use
                          value: kind,
                          decoration: const InputDecoration(
                            labelText: 'Typ av media',
                          ),
                          items: TeacherProfileMediaKind.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_kindOptionLabel(value)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              kind = value;
                              if (value ==
                                      TeacherProfileMediaKind.lessonMedia &&
                                  lessonSources.isNotEmpty) {
                                selectedLessonId = lessonSources.first.id;
                              } else if (value ==
                                      TeacherProfileMediaKind
                                          .seminarRecording &&
                                  recordingSources.isNotEmpty) {
                                selectedRecordingId = recordingSources.first.id;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        if (kind == TeacherProfileMediaKind.lessonMedia)
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
                            onChanged: (value) =>
                                setState(() => selectedLessonId = value),
                          )
                        else if (kind ==
                            TeacherProfileMediaKind.seminarRecording)
                          DropdownButtonFormField<String>(
                            // ignore: deprecated_member_use
                            value: selectedRecordingId,
                            decoration: const InputDecoration(
                              labelText: 'Välj inspelning',
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Välj en inspelning'
                                : null,
                            items: recordingSources
                                .map(
                                  (recording) => DropdownMenuItem(
                                    value: recording.id,
                                    child: Text(
                                      recording.seminarTitle ??
                                          'Livesändning ${recording.id.substring(0, 8)}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => selectedRecordingId = value),
                          )
                        else
                          TextFormField(
                            controller: urlController,
                            decoration: const InputDecoration(
                              labelText: 'Extern URL',
                              hintText: 'https://...',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Ange en URL';
                              }
                              return null;
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
                        const SizedBox(height: 12),
                        SwitchListTile(
                          value: isPublished,
                          title: const Text('Publicera direkt'),
                          onChanged: (value) =>
                              setState(() => isPublished = value),
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
                          kind: kind,
                          mediaId: switch (kind) {
                            TeacherProfileMediaKind.lessonMedia =>
                              selectedLessonId,
                            TeacherProfileMediaKind.seminarRecording =>
                              selectedRecordingId,
                            TeacherProfileMediaKind.external => null,
                          },
                          externalUrl: kind == TeacherProfileMediaKind.external
                              ? urlController.text.trim()
                              : null,
                          title: titleController.text.trim().isEmpty
                              ? null
                              : titleController.text.trim(),
                          description: descriptionController.text.trim().isEmpty
                              ? null
                              : descriptionController.text.trim(),
                          isPublished: isPublished,
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
      urlController.dispose();
    }
  }

  static Future<void> showEditDialog(
    BuildContext context,
    WidgetRef ref,
    TeacherProfileMediaItem item,
  ) async {
    final controller = ref.read(teacherProfileMediaProvider.notifier);
    final titleController = TextEditingController(text: item.title ?? '');
    final descriptionController = TextEditingController(
      text: item.description ?? '',
    );
    bool isPublished = item.isPublished;
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Redigera media'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Titel'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Beskrivning',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: isPublished,
                      onChanged: (value) => setState(() {
                        isPublished = value;
                      }),
                      title: const Text('Publicerad'),
                    ),
                  ],
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
                      await controller.updateItem(
                        item.id,
                        title: titleController.text.trim().isEmpty
                            ? null
                            : titleController.text.trim(),
                        description: descriptionController.text.trim().isEmpty
                            ? null
                            : descriptionController.text.trim(),
                        isPublished: isPublished,
                      );
                      if (context.mounted) Navigator.of(context).pop();
                    } catch (error) {
                      if (!context.mounted) return;
                      _showErrorSnackBar(context, error);
                    }
                  },
                  child: const Text('Spara ändringar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<void> confirmDelete(
    BuildContext context,
    WidgetRef ref,
    TeacherProfileMediaItem item,
  ) async {
    final controller = ref.read(teacherProfileMediaProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ta bort media'),
        content: Text(
          'Vill du ta bort "${_ProfileMediaTile._titleFor(item)}" från profilen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Avbryt'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await controller.deleteItem(item.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${_ProfileMediaTile._titleFor(item)}" borttagen från profilen.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      _showErrorSnackBar(context, error);
    }
  }

  static String _kindOptionLabel(TeacherProfileMediaKind kind) {
    switch (kind) {
      case TeacherProfileMediaKind.lessonMedia:
        return 'Lektionsmedia';
      case TeacherProfileMediaKind.seminarRecording:
        return 'Livesändning';
      case TeacherProfileMediaKind.external:
        return 'Extern länk';
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
