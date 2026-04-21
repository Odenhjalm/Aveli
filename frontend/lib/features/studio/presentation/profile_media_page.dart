import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';
import 'package:aveli/features/studio/application/home_player_library_controller.dart';
import 'package:aveli/features/studio/widgets/home_player_upload_dialog.dart';
import 'package:aveli/features/studio/widgets/home_player_upload_routing.dart';
import 'package:aveli/features/studio/widgets/wav_upload_source.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/hero_background.dart';

class StudioProfilePage extends ConsumerStatefulWidget {
  const StudioProfilePage({super.key});

  @override
  ConsumerState<StudioProfilePage> createState() => _StudioProfilePageState();
}

class _StudioProfilePageState extends ConsumerState<StudioProfilePage> {
  Timer? _libraryPoller;

  @override
  void dispose() {
    _libraryPoller?.cancel();
    super.dispose();
  }

  void _syncHomeUploadPolling(AsyncValue<HomePlayerLibraryState> libraryAsync) {
    final uploads = libraryAsync.valueOrNull?.uploads;
    final shouldPoll =
        uploads?.any((upload) {
          final mediaAssetId = (upload.mediaAssetId ?? '').trim();
          if (mediaAssetId.isEmpty) return false;
          final state = (upload.mediaState ?? 'uploaded').trim().toLowerCase();
          return state != 'ready' && state != 'failed';
        }) ??
        false;

    if (shouldPoll) {
      _libraryPoller ??= Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        ref.invalidate(homePlayerLibraryProvider);
      });
      return;
    }

    _libraryPoller?.cancel();
    _libraryPoller = null;
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(homePlayerLibraryProvider);
    _syncHomeUploadPolling(asyncState);

    final cached = asyncState.valueOrNull;
    final title = cached?.textBundle.requireValue(
      'studio_editor.profile_media.home_player_library_title',
    ) ?? '';
    if (cached != null) {
      return AppScaffold(
        title: title,
        extendBodyBehindAppBar: true,
        onBack: () => context.goNamed(AppRoute.home),
        contentPadding: const EdgeInsets.fromLTRB(16, 120, 16, 32),
        background: const HeroBackground(
          assetPath: 'images/bakgrund.png',
          opacity: 0.65,
        ),
        body: _HomePlayerLibraryBody(state: cached, isBusy: false),
      );
    }

    return AppScaffold(
      title: title,
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
          message: _backendOwnedErrorMessage(error),
          onRetry: () => ref.invalidate(homePlayerLibraryProvider),
        ),
        data: (data) => _HomePlayerLibraryBody(state: data, isBusy: false),
      ),
    );
  }
}

class _HomePlayerLibraryBody extends ConsumerWidget {
  const _HomePlayerLibraryBody({required this.state, required this.isBusy});

  final HomePlayerLibraryState state;
  final bool isBusy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(homePlayerLibraryProvider.notifier);
    final uploads = state.uploads;
    final links = state.courseLinks;
    final texts = state.textBundle;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionCard(
            title: texts.requireValue(
              'studio_editor.profile_media.home_player_uploads_title',
            ),
            subtitle: texts.requireValue(
              'studio_editor.profile_media.home_player_uploads_description',
            ),
            primary: true,
            isBusy: isBusy,
            onRefresh: () async => ref.invalidate(homePlayerLibraryProvider),
            refreshLabel: texts.requireValue(
              'studio_editor.profile_media.refresh_action',
            ),
            actions: [
              FilledButton.icon(
                onPressed: isBusy
                    ? null
                    : () async => await _uploadHomeMedia(context, ref, texts),
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  texts.requireValue('home.player_upload.submit_action'),
                ),
              ),
            ],
            child: uploads.isEmpty
                ? _HomeUploadsEmptyState(texts: texts)
                : _HomeUploadsList(
                    texts: texts,
                    uploads: uploads,
                    disabled: isBusy,
                    onToggle: (id, value) async {
                      try {
                        await controller.toggleUpload(id, value);
                      } catch (error) {
                        if (!context.mounted) return;
                        _showErrorSnackBar(
                          context,
                          error,
                          texts,
                          'studio_editor.profile_media.action_failed_error',
                        );
                      }
                    },
                    onRename: (id, title) async {
                      try {
                        await controller.renameUpload(id, title);
                      } catch (error) {
                        if (!context.mounted) return;
                        _showErrorSnackBar(
                          context,
                          error,
                          texts,
                          'studio_editor.profile_media.action_failed_error',
                        );
                      }
                    },
                    onDelete: (id, title) async {
                      final confirmed = await _confirm(
                        context,
                        texts: texts,
                        title: texts.requireValue(
                          'studio_editor.profile_media.upload_delete_title',
                        ),
                        message: texts.requireValue(
                          'studio_editor.profile_media.upload_delete_message',
                        ),
                        confirmLabel: texts.requireValue(
                          'studio_editor.profile_media.upload_delete_action',
                        ),
                      );
                      if (confirmed != true) return;
                      try {
                        await controller.deleteUpload(id);
                      } catch (error) {
                        if (!context.mounted) return;
                        _showErrorSnackBar(
                          context,
                          error,
                          texts,
                          'studio_editor.profile_media.action_failed_error',
                        );
                      }
                    },
                  ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: texts.requireValue(
              'studio_editor.profile_media.home_player_links_title',
            ),
            subtitle: texts.requireValue(
              'studio_editor.profile_media.home_player_links_description',
            ),
            primary: false,
            isBusy: isBusy,
            onRefresh: () async => ref.invalidate(homePlayerLibraryProvider),
            refreshLabel: texts.requireValue(
              'studio_editor.profile_media.refresh_action',
            ),
            actions: [
              OutlinedButton.icon(
                onPressed: isBusy
                    ? null
                    : () async => await _linkFromCourses(context, ref, texts),
                icon: const Icon(Icons.link_outlined),
                label: Text(
                  texts.requireValue(
                    'studio_editor.profile_media.home_player_link_action',
                  ),
                ),
              ),
            ],
            child: links.isEmpty
                ? _CourseLinksEmptyState(texts: texts)
                : _CourseLinksList(
                    texts: texts,
                    links: links,
                    disabled: isBusy,
                    onToggle: (id, value) async {
                      try {
                        await controller.toggleCourseLink(id, value);
                      } catch (error) {
                        if (!context.mounted) return;
                        _showErrorSnackBar(
                          context,
                          error,
                          texts,
                          'studio_editor.profile_media.action_failed_error',
                        );
                      }
                    },
                    onDelete: (id, title) async {
                      final confirmed = await _confirm(
                        context,
                        texts: texts,
                        title: texts.requireValue(
                          'studio_editor.profile_media.link_delete_title',
                        ),
                        message: texts.requireValue(
                          'studio_editor.profile_media.link_delete_message',
                        ),
                        confirmLabel: texts.requireValue(
                          'studio_editor.profile_media.link_delete_action',
                        ),
                      );
                      if (confirmed != true) return;
                      try {
                        await controller.deleteCourseLink(id);
                      } catch (error) {
                        if (!context.mounted) return;
                        _showErrorSnackBar(
                          context,
                          error,
                          texts,
                          'studio_editor.profile_media.action_failed_error',
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String? message;
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
          if (message != null && message!.trim().isNotEmpty)
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 16),
          IconButton(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

String? _backendOwnedErrorMessage(Object error) {
  final failure = AppFailure.from(error);
  final message = failure.message.trim();
  if (failure.code != null && message.isNotEmpty) {
    return message;
  }
  return null;
}

void _showErrorSnackBar(
  BuildContext context,
  Object error,
  HomePlayerTextBundle texts,
  String fallbackTextId,
) {
  final message = _backendOwnedErrorMessage(error) ?? texts.requireValue(fallbackTextId);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.primary,
    required this.isBusy,
    required this.onRefresh,
    required this.refreshLabel,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool primary;
  final bool isBusy;
  final Future<void> Function() onRefresh;
  final String refreshLabel;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      opacity: primary ? 0.16 : 0.10,
      sigmaX: 3,
      sigmaY: 3,
      borderColor: theme.colorScheme.onSurface.withValues(
        alpha: primary ? 0.12 : 0.06,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ...actions,
              const SizedBox(width: 8),
              IconButton(
                tooltip: refreshLabel,
                onPressed: isBusy ? null : () async => await onRefresh(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _HomeUploadsEmptyState extends StatelessWidget {
  const _HomeUploadsEmptyState({required this.texts});

  final HomePlayerTextBundle texts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Icon(
            Icons.library_music_outlined,
            size: 56,
            color: theme.colorScheme.primary.withValues(alpha: 0.75),
          ),
          const SizedBox(height: 10),
          Text(
            texts.requireValue(
              'studio_editor.profile_media.home_player_uploads_empty_title',
            ),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            texts.requireValue(
              'studio_editor.profile_media.home_player_uploads_empty_status',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _HomeUploadsList extends StatelessWidget {
  const _HomeUploadsList({
    required this.texts,
    required this.uploads,
    required this.disabled,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
  });

  final HomePlayerTextBundle texts;
  final List<HomePlayerUploadItem> uploads;
  final bool disabled;
  final Future<void> Function(String id, bool value) onToggle;
  final Future<void> Function(String id, String title) onRename;
  final Future<void> Function(String id, String title) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dividerColor = theme.colorScheme.onSurface.withValues(alpha: 0.10);
    return Column(
      children: [
        Divider(height: 1, thickness: 1, color: dividerColor),
        for (final upload in uploads) ...[
          _HomeUploadTile(
            key: ValueKey(upload.id),
            texts: texts,
            upload: upload,
            disabled: disabled,
            onToggle: onToggle,
            onRename: onRename,
            onDelete: onDelete,
          ),
          Divider(height: 1, thickness: 1, color: dividerColor, indent: 34),
        ],
      ],
    );
  }
}

class _HomeUploadTile extends StatefulWidget {
  const _HomeUploadTile({
    super.key,
    required this.texts,
    required this.upload,
    required this.disabled,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
  });

  final HomePlayerTextBundle texts;
  final HomePlayerUploadItem upload;
  final bool disabled;
  final Future<void> Function(String id, bool value) onToggle;
  final Future<void> Function(String id, String title) onRename;
  final Future<void> Function(String id, String title) onDelete;

  @override
  State<_HomeUploadTile> createState() => _HomeUploadTileState();
}

class _HomeUploadTileState extends State<_HomeUploadTile> {
  late final TextEditingController _titleController;
  late final FocusNode _titleFocusNode;

  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _titleFocusNode = FocusNode();
    _titleFocusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _HomeUploadTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing) {
      _titleController.text = widget.upload.title;
    }
  }

  @override
  void dispose() {
    _titleFocusNode.removeListener(_onFocusChanged);
    _titleFocusNode.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_titleFocusNode.hasFocus && _editing && !_saving) {
      _cancelEditing();
    }
  }

  void _startEditing() {
    if (widget.disabled || _saving) return;
    setState(() {
      _editing = true;
      _titleController.text = widget.upload.title;
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

  void _cancelEditing() {
    if (!_editing) return;
    setState(() => _editing = false);
  }

  Future<void> _saveEditing() async {
    final trimmed = _titleController.text.trim();
    if (trimmed.isEmpty) {
      _cancelEditing();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.texts.requireValue(
              'studio_editor.profile_media.title_required_error',
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    if (trimmed == widget.upload.title) {
      _cancelEditing();
      return;
    }

    setState(() {
      _editing = false;
      _saving = true;
    });

    try {
      await widget.onRename(widget.upload.id, trimmed);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const icon = Icons.headphones;
    final typeLabel = widget.texts.requireValue(
      'studio_editor.profile_media.audio_kind_label',
    );
    final isDisabled = widget.disabled || _saving;
    final mediaAssetId = (widget.upload.mediaAssetId ?? '').trim();
    final mediaState = (widget.upload.mediaState ?? 'uploaded')
        .trim()
        .toLowerCase();
    final showsProcessing = mediaAssetId.isNotEmpty && mediaState != 'ready';
    final processingError = mediaState == 'failed';
    final processingLabel = processingError
        ? widget.texts.requireValue(
            'studio_editor.profile_media.processing_failed_error',
          )
        : widget.texts.requireValue(
            'studio_editor.profile_media.processing_status',
          );

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: widget.upload.active ? 1 : 0.7,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 22,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_editing)
                    Focus(
                      onKeyEvent: (_, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.escape) {
                          _cancelEditing();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _titleController,
                        focusNode: _titleFocusNode,
                        enabled: !isDisabled,
                        maxLines: 1,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) async => await _saveEditing(),
                        style: titleStyle,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: UnderlineInputBorder(),
                        ),
                      ),
                    )
                  else
                    MouseRegion(
                      cursor: isDisabled
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: isDisabled ? null : _startEditing,
                        child: Text(
                          widget.upload.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    typeLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (showsProcessing) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!processingError)
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        if (!processingError) const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            processingLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: processingError
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: processingError
                                  ? FontWeight.w600
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: widget.texts.requireValue(
                'studio_editor.profile_media.upload_delete_action',
              ),
              onPressed: isDisabled
                  ? null
                  : () async => await widget.onDelete(
                      widget.upload.id,
                      widget.upload.title,
                    ),
              icon: const Icon(Icons.delete_outline),
            ),
            Switch.adaptive(
              value: widget.upload.active,
              onChanged: isDisabled
                  ? null
                  : (value) async =>
                        await widget.onToggle(widget.upload.id, value),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseLinksEmptyState extends StatelessWidget {
  const _CourseLinksEmptyState({required this.texts});

  final HomePlayerTextBundle texts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Icon(
            Icons.link_outlined,
            size: 52,
            color: theme.colorScheme.primary.withValues(alpha: 0.75),
          ),
          const SizedBox(height: 10),
          Text(
            texts.requireValue(
              'studio_editor.profile_media.home_player_links_empty_title',
            ),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            texts.requireValue(
              'studio_editor.profile_media.home_player_links_empty_status',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CourseLinksList extends StatelessWidget {
  const _CourseLinksList({
    required this.texts,
    required this.links,
    required this.disabled,
    required this.onToggle,
    required this.onDelete,
  });

  final HomePlayerTextBundle texts;
  final List<HomePlayerCourseLinkItem> links;
  final bool disabled;
  final Future<void> Function(String id, bool value) onToggle;
  final Future<void> Function(String id, String title) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dividerColor = theme.colorScheme.onSurface.withValues(alpha: 0.10);
    return Column(
      children: [
        Divider(height: 1, thickness: 1, color: dividerColor),
        for (final link in links) ...[
          _CourseLinkTile(
            texts: texts,
            link: link,
            disabled: disabled,
            onToggle: onToggle,
            onDelete: onDelete,
          ),
          Divider(height: 1, thickness: 1, color: dividerColor, indent: 34),
        ],
      ],
    );
  }
}

class _CourseLinkTile extends StatelessWidget {
  const _CourseLinkTile({
    required this.texts,
    required this.link,
    required this.disabled,
    required this.onToggle,
    required this.onDelete,
  });

  final HomePlayerTextBundle texts;
  final HomePlayerCourseLinkItem link;
  final bool disabled;
  final Future<void> Function(String id, bool value) onToggle;
  final Future<void> Function(String id, String title) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const icon = Icons.headphones;
    final statusLabel = _statusLabel(link.status);
    final statusTone = _statusTone(link.status);
    final canToggle = link.status == HomePlayerCourseLinkStatus.active;
    final subtitleParts = <String>[
      if (link.courseTitle.isNotEmpty) link.courseTitle,
    ];
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: link.enabled ? 1 : 0.7,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 22,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (subtitleParts.isNotEmpty)
                        Text(
                          subtitleParts.join(' • '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      _StatusChip(label: statusLabel, tone: statusTone),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: texts.requireValue(
                'studio_editor.profile_media.link_delete_action',
              ),
              onPressed: disabled
                  ? null
                  : () async => await onDelete(link.id, link.title),
              icon: const Icon(Icons.link_off_outlined),
            ),
            Switch.adaptive(
              value: link.enabled,
              onChanged: disabled || !canToggle
                  ? null
                  : (value) async => await onToggle(link.id, value),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(HomePlayerCourseLinkStatus status) {
    switch (status) {
      case HomePlayerCourseLinkStatus.active:
        return texts.requireValue(
          'studio_editor.profile_media.course_link_active_status',
        );
      case HomePlayerCourseLinkStatus.sourceMissing:
        return texts.requireValue(
          'studio_editor.profile_media.course_link_source_missing_error',
        );
      case HomePlayerCourseLinkStatus.courseUnpublished:
        return texts.requireValue(
          'studio_editor.profile_media.course_link_unpublished_status',
        );
    }
  }

  _StatusTone _statusTone(HomePlayerCourseLinkStatus status) {
    switch (status) {
      case HomePlayerCourseLinkStatus.active:
        return _StatusTone.ok;
      case HomePlayerCourseLinkStatus.sourceMissing:
        return _StatusTone.error;
      case HomePlayerCourseLinkStatus.courseUnpublished:
        return _StatusTone.warn;
    }
  }
}

enum _StatusTone { ok, warn, error }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

  final String label;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      _StatusTone.ok => (
        scheme.primary.withValues(alpha: 0.14),
        scheme.primary,
      ),
      _StatusTone.warn => (
        scheme.tertiary.withValues(alpha: 0.14),
        scheme.tertiary,
      ),
      _StatusTone.error => (scheme.error.withValues(alpha: 0.14), scheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required HomePlayerTextBundle texts,
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            texts.requireValue('studio_editor.profile_media.cancel_action'),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

Future<void> _uploadHomeMedia(
  BuildContext context,
  WidgetRef ref,
  HomePlayerTextBundle texts,
) async {
  final picked = await pickMediaFile();
  if (picked == null) return;
  if (!context.mounted) return;

  final contentType = (picked.mimeType?.isNotEmpty ?? false)
      ? picked.mimeType!
      : _guessContentType(picked.name);
  final route = detectHomePlayerUploadRoute(
    mimeType: contentType,
    filename: picked.name,
  );
  final errorTextId = homePlayerUploadUnsupportedTextId(route);
  if (errorTextId != null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texts.requireValue(errorTextId))),
    );
    return;
  }

  final suggested = _suggestTitleFromFilename(picked.name);
  final title = await _promptRequiredTitle(
    context,
    texts: texts,
    title: texts.requireValue('studio_editor.profile_media.upload_prompt_title'),
    hint: texts.requireValue('studio_editor.profile_media.upload_prompt_hint'),
    initialValue: suggested,
    confirmLabel: texts.requireValue('home.player_upload.submit_action'),
  );
  if (title == null) return;
  if (!context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => HomePlayerUploadDialog(
      file: picked,
      title: title,
      contentType: contentType,
      textBundle: texts,
    ),
  );

  if (ok == true && context.mounted) {
    ref.invalidate(homePlayerLibraryProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          texts.requireValue('studio_editor.profile_media.upload_ready_status'),
        ),
      ),
    );
  }
}

Future<void> _linkFromCourses(
  BuildContext context,
  WidgetRef ref,
  HomePlayerTextBundle texts,
) async {
  final state = ref.read(homePlayerLibraryProvider).valueOrNull;
  final sources = state?.courseMedia ?? const <TeacherProfileLessonSource>[];
  final audioSources = sources
      .where(_isHomeAudioCourseSource)
      .toList(growable: false);
  if (audioSources.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          texts.requireValue(
            'studio_editor.profile_media.no_course_audio_status',
          ),
        ),
      ),
    );
    return;
  }
  if (!context.mounted) return;

  final picked = await _pickCourseMedia(context, audioSources, texts);
  if (picked == null) return;
  if (!context.mounted) return;

  final suggested = (picked.lessonTitle ?? '').trim();
  final title = await _promptRequiredTitle(
    context,
    texts: texts,
    title: texts.requireValue('studio_editor.profile_media.link_prompt_title'),
    hint: texts.requireValue('studio_editor.profile_media.link_prompt_hint'),
    initialValue: suggested,
    confirmLabel: texts.requireValue(
      'studio_editor.profile_media.home_player_link_action',
    ),
  );
  if (title == null) return;
  if (!context.mounted) return;

  final controller = ref.read(homePlayerLibraryProvider.notifier);
  try {
    await controller.createCourseLink(lessonMediaId: picked.id, title: title);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          texts.requireValue('studio_editor.profile_media.link_created_status'),
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    _showErrorSnackBar(
      context,
      error,
      texts,
      'studio_editor.profile_media.action_failed_error',
    );
  }
}

Future<String?> _promptRequiredTitle(
  BuildContext context, {
  required HomePlayerTextBundle texts,
  required String title,
  required String hint,
  required String initialValue,
  required String confirmLabel,
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => Navigator.of(context).pop(controller.text.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(
            texts.requireValue('studio_editor.profile_media.cancel_action'),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  final trimmed = result?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

Future<TeacherProfileLessonSource?> _pickCourseMedia(
  BuildContext context,
  List<TeacherProfileLessonSource> sources,
  HomePlayerTextBundle texts,
) async {
  final audioSources = sources
      .where(_isHomeAudioCourseSource)
      .toList(growable: false);

  return showModalBottomSheet<TeacherProfileLessonSource>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final height = MediaQuery.of(sheetContext).size.height * 0.8;
      final searchController = TextEditingController();
      return SizedBox(
        height: height,
        child: StatefulBuilder(
          builder: (context, setState) {
            final query = searchController.text.trim().toLowerCase();
            final filtered = query.isEmpty
                ? audioSources
                : audioSources
                      .where((source) {
                        final course = (source.courseTitle ?? '').toLowerCase();
                        final lesson = (source.lessonTitle ?? '').toLowerCase();
                        return course.contains(query) || lesson.contains(query);
                      })
                      .toList(growable: false);
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    texts.requireValue(
                      'studio_editor.profile_media.course_picker_title',
                    ),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: texts.requireValue(
                        'studio_editor.profile_media.course_picker_search_hint',
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              texts.requireValue(
                                'studio_editor.profile_media.course_picker_empty_status',
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final source = filtered[index];
                              final courseTitle = (source.courseTitle ?? '')
                                  .trim();
                              final lessonTitle = (source.lessonTitle ?? '')
                                  .trim();
                              final subtitleParts = <String>[
                                if (courseTitle.isNotEmpty) courseTitle,
                                if (lessonTitle.isNotEmpty) lessonTitle,
                              ];
                              return ListTile(
                                leading: const Icon(Icons.headphones),
                                title: Text(
                                  lessonTitle.isNotEmpty
                                      ? lessonTitle
                                      : (courseTitle.isNotEmpty
                                            ? courseTitle
                                            : ''),
                                ),
                                subtitle: subtitleParts.isEmpty
                                    ? null
                                    : Text(
                                        subtitleParts.join(' • '),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                onTap: () =>
                                    Navigator.of(sheetContext).pop(source),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

String _suggestTitleFromFilename(String filename) {
  final name = filename.trim();
  if (name.isEmpty) return '';
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return name;
  return name.substring(0, dot);
}

bool _isHomeAudioCourseSource(TeacherProfileLessonSource source) {
  final kind = source.kind.trim().toLowerCase();
  final contentType = (source.contentType ?? '').trim().toLowerCase();
  return kind.contains('audio') || contentType.startsWith('audio/');
}

String _guessContentType(String filename) {
  final segments = filename.toLowerCase().split('.');
  final ext = segments.length > 1 ? segments.last : '';
  return switch (ext) {
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'aac' => 'audio/aac',
    'ogg' => 'audio/ogg',
    'wav' => 'audio/wav',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'm4v' => 'video/x-m4v',
    'webm' => 'video/webm',
    'mkv' => 'video/x-matroska',
    _ => 'application/octet-stream',
  };
}
