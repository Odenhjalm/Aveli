import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';
import 'package:aveli/features/home/application/home_providers.dart';
import 'package:aveli/features/media/application/media_playback_controller.dart';
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
              'Här väljer du vilken media som får visas i Home-spelaren.\nEndast namngiven ljud/video som du aktivt väljer här kan visas för elever.',
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
    final rows = <_UnifiedMediaRow>[];

    for (final item in state.items) {
      if (item.mediaKind == TeacherProfileMediaKind.external) continue;
      final title = item.title?.trim();
      if (title == null || title.isEmpty) continue;
      final source = item.source;
      if (item.mediaKind == TeacherProfileMediaKind.lessonMedia) {
        final lesson = source.lessonMedia;
        if (lesson == null) continue;
        final kind = lesson.kind.toLowerCase();
        final contentType = (lesson.contentType ?? '').toLowerCase();
        final isAudio =
            kind.contains('audio') || contentType.startsWith('audio/');
        final isVideo =
            kind.contains('video') || contentType.startsWith('video/');
        if (!isAudio && !isVideo) continue;
        rows.add(
          _UnifiedMediaRow(
            itemId: item.id,
            sourceMediaId: item.mediaId,
            title: title,
            courseTitle: _courseTitleForLessonMediaSource(lesson),
            enabledForHomePlayer: item.enabledForHomePlayer,
            icon: isVideo ? Icons.videocam_outlined : Icons.headphones,
            durationSeconds: lesson.durationSeconds,
            createdAt: item.createdAt,
          ),
        );
        continue;
      }
      if (item.mediaKind == TeacherProfileMediaKind.seminarRecording) {
        final recording = source.seminarRecording;
        if (recording == null) continue;
        rows.add(
          _UnifiedMediaRow(
            itemId: item.id,
            sourceMediaId: item.mediaId,
            title: title,
            courseTitle: _courseTitleForRecordingSource(recording),
            enabledForHomePlayer: item.enabledForHomePlayer,
            icon: Icons.mic_external_on_outlined,
            durationSeconds: recording.durationSeconds,
            createdAt: item.createdAt,
          ),
        );
        continue;
      }
      rows.add(
        _UnifiedMediaRow(
          itemId: item.id,
          sourceMediaId: item.mediaId,
          title: title,
          courseTitle: _courseTitleForLessonMediaSource(
            item.source.lessonMedia,
          ),
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

  static int _compareRows(_UnifiedMediaRow a, _UnifiedMediaRow b) {
    final aCourse = a.courseTitle.trim();
    final bCourse = b.courseTitle.trim();

    final aIsFallback = aCourse == _fallbackCourse;
    final bIsFallback = bCourse == _fallbackCourse;
    if (aIsFallback != bIsFallback) return aIsFallback ? 1 : -1;

    final courseDiff = aCourse.toLowerCase().compareTo(bCourse.toLowerCase());
    if (courseDiff != 0) return courseDiff;

    final titleDiff = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    if (titleDiff != 0) return titleDiff;

    final aDate = a.createdAt;
    final bDate = b.createdAt;
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  }

  static String _courseTitleForLessonMediaSource(
    TeacherProfileLessonSource? lesson,
  ) {
    final course = lesson?.courseTitle?.trim();
    if (course != null && course.isNotEmpty) return course;
    return _fallbackCourse;
  }

  static String _courseTitleForRecordingSource(
    TeacherProfileRecordingSource recording,
  ) {
    final course = _courseTitleFromMetadata(recording.metadata)?.trim();
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
}

class _UnifiedMediaRow {
  const _UnifiedMediaRow({
    required this.itemId,
    required this.sourceMediaId,
    required this.title,
    required this.courseTitle,
    required this.enabledForHomePlayer,
    required this.icon,
    required this.durationSeconds,
    required this.createdAt,
  });

  final String itemId;
  final String? sourceMediaId;
  final String title;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 1, thickness: 1, color: dividerColor),
        for (var index = 0; index < rows.length; index++) ...[
          _UnifiedMediaTile(row: rows[index], disabled: disabled),
          Divider(height: 1, thickness: 1, color: dividerColor, indent: 34),
        ],
      ],
    );
  }
}

class _UnifiedMediaTile extends ConsumerStatefulWidget {
  const _UnifiedMediaTile({required this.row, required this.disabled});

  final _UnifiedMediaRow row;
  final bool disabled;

  @override
  ConsumerState<_UnifiedMediaTile> createState() => _UnifiedMediaTileState();
}

class _UnifiedMediaTileState extends ConsumerState<_UnifiedMediaTile> {
  late final TextEditingController _titleController;
  late final FocusNode _titleFocusNode;
  bool _editingTitle = false;
  bool _savingTitle = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.row.title);
    _titleFocusNode = FocusNode();
    _titleFocusNode.addListener(_handleTitleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _UnifiedMediaTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editingTitle && oldWidget.row.title != widget.row.title) {
      _titleController.text = widget.row.title;
    }
  }

  @override
  void dispose() {
    _titleFocusNode.removeListener(_handleTitleFocusChange);
    _titleFocusNode.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _handleTitleFocusChange() {
    if (_editingTitle && !_titleFocusNode.hasFocus) {
      _commitTitle(saveOnBlur: true);
    }
  }

  void _startEditingTitle() {
    if (widget.disabled || _savingTitle) return;
    setState(() {
      _editingTitle = true;
      _titleController.text = widget.row.title;
      _titleController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _titleController.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _titleFocusNode.requestFocus();
    });
  }

  Future<void> _commitTitle({bool saveOnBlur = false}) async {
    if (!_editingTitle || _savingTitle) return;
    final next = _titleController.text.trim();
    final current = widget.row.title.trim();

    if (next.isEmpty) {
      if (!mounted) return;
      _titleController.text = widget.row.title;
      setState(() => _editingTitle = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Titeln får inte vara tom.')),
      );
      return;
    }

    if (next == current) {
      if (!mounted) return;
      setState(() => _editingTitle = false);
      return;
    }

    setState(() => _savingTitle = true);

    try {
      await ref.read(teacherProfileMediaProvider.notifier).renameTitle(
            widget.row.itemId,
            next,
          );

      ref.invalidate(homeAudioProvider);

      final playback = ref.read(mediaPlaybackControllerProvider);
      if (playback.isPlaying && playback.currentMediaId != null) {
        final notifier = ref.read(mediaPlaybackControllerProvider.notifier);
        notifier.updateTitleIfActive(widget.row.itemId, next);
        final sourceId = widget.row.sourceMediaId;
        if (sourceId != null && sourceId.isNotEmpty) {
          notifier.updateTitleIfActive(sourceId, next);
        }
      }

      if (!mounted) return;
      setState(() => _editingTitle = false);
    } catch (error) {
      if (mounted) {
        _showErrorSnackBar(context, error);
        if (saveOnBlur) {
          setState(() => _editingTitle = false);
        }
      }
    } finally {
      if (mounted) setState(() => _savingTitle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(teacherProfileMediaProvider.notifier);
    final theme = Theme.of(context);
    final row = widget.row;
    final dimmed = !row.enabledForHomePlayer;
    final durationLabel = _formatDuration(row.durationSeconds);
    final metaParts = <String>[
      if (durationLabel != null) durationLabel,
      'Kurs: ${row.courseTitle}',
    ];
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
                  _editingTitle
                      ? TextField(
                          controller: _titleController,
                          focusNode: _titleFocusNode,
                          enabled: !widget.disabled && !_savingTitle,
                          maxLines: 1,
                          textInputAction: TextInputAction.done,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            suffixIcon: _savingTitle
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    tooltip: 'Spara',
                                    onPressed: widget.disabled || _savingTitle
                                        ? null
                                        : () async {
                                            FocusScope.of(context).unfocus();
                                            await _commitTitle();
                                          },
                                    icon: const Icon(Icons.check_rounded),
                                  ),
                          ),
                          onSubmitted: (_) async {
                            FocusScope.of(context).unfocus();
                            await _commitTitle();
                          },
                        )
                      : InkWell(
                          onTap:
                              widget.disabled || _savingTitle
                                  ? null
                                  : _startEditingTitle,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              row.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                  const SizedBox(height: 4),
                  Text(
                    metaParts.join(' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: row.enabledForHomePlayer,
              onChanged: widget.disabled
                  ? null
                  : (value) async {
                      try {
                        await controller.toggleHomePlayer(row.itemId, value);
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
          'När du laddar upp ljud eller video och ger filen ett namn visas den här. Seminarieinspelningar visas också här.',
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
