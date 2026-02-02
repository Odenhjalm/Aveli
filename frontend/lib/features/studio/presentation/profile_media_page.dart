import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';
import 'package:aveli/features/studio/application/profile_media_controller.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
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
    final rows = _buildUnifiedRows(state);
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
                      : () => ref
                            .read(teacherProfileMediaProvider.notifier)
                            .refresh(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Här väljer du vilken av din media som får visas i Home-spelaren.\nEndast media du aktivt väljer här kan visas för elever.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            if (rows.isEmpty)
              const _EmptyState()
            else
              _UnifiedMediaList(rows: rows, disabled: isBusy),
          ],
        ),
      ),
    );
  }

  static const _fallbackCourse = 'Allmän / Ej kursbunden';

  static List<_UnifiedMediaRow> _buildUnifiedRows(
    TeacherProfileMediaState state,
  ) {
    final itemsBySourceKey = <String, TeacherProfileMediaItem>{};
    for (final item in state.items) {
      final id = item.mediaId?.trim();
      if (id == null || id.isEmpty) continue;
      itemsBySourceKey[_sourceKey(item.mediaKind, id)] = item;
    }

    final sourceKeys = <String>{};
    final rows = <_UnifiedMediaRow>[];

    for (final lesson in state.lessonSources) {
      final key = _sourceKey(TeacherProfileMediaKind.lessonMedia, lesson.id);
      sourceKeys.add(key);
      final item = itemsBySourceKey[key];
      rows.add(
        _UnifiedMediaRow(
          kind: TeacherProfileMediaKind.lessonMedia,
          mediaId: lesson.id,
          filename:
              _filenameForLesson(lesson, item) ?? _titleForLesson(lesson, item),
          courseTitle: _courseTitleForLesson(lesson, item),
          enabledForHomePlayer: item?.enabledForHomePlayer ?? false,
          icon: _iconForLesson(lesson),
          durationSeconds:
              lesson.durationSeconds ??
              item?.source.lessonMedia?.durationSeconds,
          createdAt: item?.createdAt ?? lesson.createdAt,
        ),
      );
    }

    for (final recording in state.recordingSources) {
      final key = _sourceKey(
        TeacherProfileMediaKind.seminarRecording,
        recording.id,
      );
      sourceKeys.add(key);
      final item = itemsBySourceKey[key];
      rows.add(
        _UnifiedMediaRow(
          kind: TeacherProfileMediaKind.seminarRecording,
          mediaId: recording.id,
          filename:
              _filenameForRecording(recording, item) ??
              _titleForRecording(recording, item),
          courseTitle: _courseTitleForRecording(recording, item),
          enabledForHomePlayer: item?.enabledForHomePlayer ?? false,
          icon: Icons.mic_external_on_outlined,
          durationSeconds:
              recording.durationSeconds ??
              item?.source.seminarRecording?.durationSeconds,
          createdAt: item?.createdAt ?? recording.createdAt,
        ),
      );
    }

    for (final item in state.items) {
      if (item.mediaKind == TeacherProfileMediaKind.external) continue;
      final id = item.mediaId?.trim();
      if (id == null || id.isEmpty) continue;
      final key = _sourceKey(item.mediaKind, id);
      if (sourceKeys.contains(key)) continue;
      rows.add(
        _UnifiedMediaRow(
          kind: item.mediaKind,
          mediaId: id,
          filename: _filenameForItem(item) ?? _titleForItem(item),
          courseTitle: _courseTitleForItem(item),
          enabledForHomePlayer: item.enabledForHomePlayer,
          icon: _iconForItem(item),
          durationSeconds:
              item.source.lessonMedia?.durationSeconds ??
              item.source.seminarRecording?.durationSeconds,
          createdAt: item.createdAt,
        ),
      );
    }

    rows.sort(_compareRows);
    return rows;
  }

  static String _sourceKey(TeacherProfileMediaKind kind, String id) {
    return '${kind.apiValue}::$id';
  }

  static int _compareRows(_UnifiedMediaRow a, _UnifiedMediaRow b) {
    final aCourse = a.courseTitle.trim();
    final bCourse = b.courseTitle.trim();

    final aIsFallback = aCourse == _fallbackCourse;
    final bIsFallback = bCourse == _fallbackCourse;
    if (aIsFallback != bIsFallback) return aIsFallback ? 1 : -1;

    final courseDiff = aCourse.toLowerCase().compareTo(bCourse.toLowerCase());
    if (courseDiff != 0) return courseDiff;

    final titleDiff = a.filename.toLowerCase().compareTo(
      b.filename.toLowerCase(),
    );
    if (titleDiff != 0) return titleDiff;

    final aDate = a.createdAt;
    final bDate = b.createdAt;
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  }

  static String _titleForLesson(
    TeacherProfileLessonSource lesson,
    TeacherProfileMediaItem? item,
  ) {
    final explicit = item?.title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final lessonTitle = lesson.lessonTitle?.trim();
    if (lessonTitle != null && lessonTitle.isNotEmpty) return lessonTitle;
    final fallback = item?.source.lessonMedia?.lessonTitle?.trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return 'Lektionsmedia';
  }

  static String _titleForRecording(
    TeacherProfileRecordingSource recording,
    TeacherProfileMediaItem? item,
  ) {
    final explicit = item?.title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final seminarTitle = recording.seminarTitle?.trim();
    if (seminarTitle != null && seminarTitle.isNotEmpty) return seminarTitle;
    final fallback = item?.source.seminarRecording?.seminarTitle?.trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;
    final basename = _basename(recording.assetUrl);
    if (basename != null) return basename;
    return 'Livesändning';
  }

  static String? _filenameForLesson(
    TeacherProfileLessonSource lesson,
    TeacherProfileMediaItem? item,
  ) {
    final storagePath =
        (lesson.storagePath ?? item?.source.lessonMedia?.storagePath)?.trim();
    final candidate =
        _basename(storagePath) ??
        _basename(lesson.signedUrl) ??
        _basename(lesson.downloadUrl);
    if (candidate == null) return null;
    final stripped = candidate.replaceFirst(RegExp(r'^\\d{10,}_'), '').trim();
    return stripped.isNotEmpty ? stripped : candidate.trim();
  }

  static String? _filenameForRecording(
    TeacherProfileRecordingSource recording,
    TeacherProfileMediaItem? item,
  ) {
    final metadataName = _stringFromMetadata(recording.metadata, const [
      'original_name',
      'originalName',
      'filename',
      'file_name',
      'name',
    ]);
    if (metadataName != null) return metadataName;
    return _basename(recording.assetUrl) ??
        _basename(item?.source.seminarRecording?.assetUrl);
  }

  static String? _filenameForItem(TeacherProfileMediaItem item) {
    switch (item.mediaKind) {
      case TeacherProfileMediaKind.lessonMedia:
        return _basename(
          item.source.lessonMedia?.storagePath,
        )?.replaceFirst(RegExp(r'^\\d{10,}_'), '').trim();
      case TeacherProfileMediaKind.seminarRecording:
        return _basename(item.source.seminarRecording?.assetUrl);
      case TeacherProfileMediaKind.external:
        return null;
    }
  }

  static String _titleForItem(TeacherProfileMediaItem item) {
    final explicit = item.title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    switch (item.mediaKind) {
      case TeacherProfileMediaKind.lessonMedia:
        return item.source.lessonMedia?.lessonTitle?.trim().isNotEmpty == true
            ? item.source.lessonMedia!.lessonTitle!.trim()
            : 'Lektionsmedia';
      case TeacherProfileMediaKind.seminarRecording:
        return item.source.seminarRecording?.seminarTitle?.trim().isNotEmpty ==
                true
            ? item.source.seminarRecording!.seminarTitle!.trim()
            : 'Livesändning';
      case TeacherProfileMediaKind.external:
        return item.externalUrl ?? 'Extern länk';
    }
  }

  static String _courseTitleForLesson(
    TeacherProfileLessonSource lesson,
    TeacherProfileMediaItem? item,
  ) {
    final course = (lesson.courseTitle ?? item?.source.lessonMedia?.courseTitle)
        ?.trim();
    if (course != null && course.isNotEmpty) return course;
    return _fallbackCourse;
  }

  static String _courseTitleForRecording(
    TeacherProfileRecordingSource recording,
    TeacherProfileMediaItem? item,
  ) {
    final course =
        (_courseTitleFromMetadata(recording.metadata) ??
                item?.source.lessonMedia?.courseTitle)
            ?.trim();
    if (course != null && course.isNotEmpty) return course;
    return _fallbackCourse;
  }

  static String _courseTitleForItem(TeacherProfileMediaItem item) {
    final course = item.source.lessonMedia?.courseTitle?.trim();
    if (course != null && course.isNotEmpty) return course;
    return _fallbackCourse;
  }

  static String? _courseTitleFromMetadata(Map<String, dynamic> metadata) {
    return _stringFromMetadata(metadata, const [
      'course_title',
      'courseTitle',
      'course_name',
      'courseName',
      'course',
    ]);
  }

  static String? _stringFromMetadata(
    Map<String, dynamic> metadata,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = metadata[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static IconData _iconForLesson(TeacherProfileLessonSource lesson) {
    final kind = lesson.kind.toLowerCase();
    if (kind.contains('video')) return Icons.videocam_outlined;
    if (kind.contains('image') || kind.contains('bild')) {
      return Icons.image_outlined;
    }
    if (kind.contains('audio') || kind.contains('ljud')) {
      return Icons.headphones;
    }
    return Icons.play_circle_outline;
  }

  static IconData _iconForItem(TeacherProfileMediaItem item) {
    switch (item.mediaKind) {
      case TeacherProfileMediaKind.lessonMedia:
        return Icons.headphones;
      case TeacherProfileMediaKind.seminarRecording:
        return Icons.mic_external_on_outlined;
      case TeacherProfileMediaKind.external:
        return Icons.link;
    }
  }

  static String? _basename(String? path) {
    if (path == null) return null;
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    final withoutQuery = trimmed.split('?').first;
    final segments = withoutQuery.split('/');
    final last = segments.isNotEmpty ? segments.last : withoutQuery;
    if (last.isEmpty) return null;
    return Uri.decodeComponent(last);
  }
}

class _UnifiedMediaRow {
  const _UnifiedMediaRow({
    required this.kind,
    required this.mediaId,
    required this.filename,
    required this.courseTitle,
    required this.enabledForHomePlayer,
    required this.icon,
    required this.durationSeconds,
    required this.createdAt,
  });

  final TeacherProfileMediaKind kind;
  final String mediaId;
  final String filename;
  final String courseTitle;
  final bool enabledForHomePlayer;
  final IconData icon;
  final int? durationSeconds;
  final DateTime? createdAt;
}

class _UnifiedMediaList extends StatelessWidget {
  const _UnifiedMediaList({required this.rows, required this.disabled});

  final List<_UnifiedMediaRow> rows;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dividerColor = theme.colorScheme.onSurface.withValues(alpha: 0.10);
    final grouped = <String, List<_UnifiedMediaRow>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.courseTitle, () => []).add(row);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
            child: Text(
              entry.key,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: dividerColor),
          for (var index = 0; index < entry.value.length; index++) ...[
            _UnifiedMediaTile(row: entry.value[index], disabled: disabled),
            if (index != entry.value.length - 1)
              Divider(height: 1, thickness: 1, color: dividerColor, indent: 34),
          ],
        ],
      ],
    );
  }
}

class _UnifiedMediaTile extends ConsumerWidget {
  const _UnifiedMediaTile({required this.row, required this.disabled});

  final _UnifiedMediaRow row;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(teacherProfileMediaProvider.notifier);
    final theme = Theme.of(context);
    final dimmed = !row.enabledForHomePlayer;
    final durationLabel = _formatDuration(row.durationSeconds);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      opacity: dimmed ? 0.68 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              row.icon,
              size: 22,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.filename,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (durationLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      durationLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch.adaptive(
              value: row.enabledForHomePlayer,
              onChanged: disabled
                  ? null
                  : (value) async {
                      try {
                        await controller.setHomePlayerForSource(
                          kind: row.kind,
                          mediaId: row.mediaId,
                          enabled: value,
                        );
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

  String? _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return null;
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
          'När du lägger till ljud, video eller bilder i dina lektioner (eller spelar in ett seminarium) visas de här.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
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

void _showErrorSnackBar(BuildContext context, Object error) {
  final failure = AppFailure.from(error);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(failure.message),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}
