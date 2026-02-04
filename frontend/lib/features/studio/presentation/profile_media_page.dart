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
    if (cached != null) {
      return AppScaffold(
        title: 'Home-spelarens bibliotek',
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
      title: 'Home-spelarens bibliotek',
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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionCard(
            title: 'Media för Home-spelaren',
            subtitle:
                'Ladda upp ljud/video direkt för Home. Dessa filer är fristående från kurser. Tar du bort en fil här raderas den helt.',
            primary: true,
            isBusy: isBusy,
            onRefresh: () async => ref.invalidate(homePlayerLibraryProvider),
            actions: [
              FilledButton.icon(
                onPressed: isBusy
                    ? null
                    : () async => await _uploadHomeMedia(context, ref),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Ladda upp'),
              ),
            ],
            child: uploads.isEmpty
                ? const _HomeUploadsEmptyState()
                : _HomeUploadsList(
                    uploads: uploads,
                    disabled: isBusy,
                    onToggle: (id, value) async {
                      try {
                        await controller.toggleUpload(id, value);
                      } catch (error) {
                        if (!context.mounted) return;
                        _showErrorSnackBar(context, error);
                      }
                    },
                    onRename: (id, title) async {
                      try {
                        await controller.renameUpload(id, title);
                      } catch (error) {
                        if (!context.mounted) return;
                        _showErrorSnackBar(context, error);
                      }
                    },
                    onDelete: (id, title) async {
                      final confirmed = await _confirm(
                        context,
                        title: 'Ta bort uppladdad fil',
                        message:
                            'Vill du ta bort "$title" från Home-spelarens bibliotek?\n\nFilen raderas helt och går inte att ångra.',
                        confirmLabel: 'Ta bort',
                      );
                      if (confirmed != true) return;
                      try {
                        await controller.deleteUpload(id);
                      } catch (error) {
                        if (!context.mounted) return;
                        _showErrorSnackBar(context, error);
                      }
                    },
                  ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Länkat från kurser',
            subtitle:
                'Här ser du media som är länkat från kursmaterial. Du kan slå på/av länken eller ta bort länken utan att påverka originalfilen.\nInga uppladdningar görs här.',
            primary: false,
            isBusy: isBusy,
            onRefresh: () async => ref.invalidate(homePlayerLibraryProvider),
            actions: [
              OutlinedButton.icon(
                onPressed: isBusy
                    ? null
                    : () async => await _linkFromCourses(context, ref),
                icon: const Icon(Icons.link_outlined),
                label: const Text('Länka media'),
              ),
            ],
            child: links.isEmpty
                ? const _CourseLinksEmptyState()
                : _CourseLinksList(
                    links: links,
                    disabled: isBusy,
                    onToggle: (id, value) async {
                      try {
                        await controller.toggleCourseLink(id, value);
                      } catch (error) {
                        if (!context.mounted) return;
                        _showErrorSnackBar(context, error);
                      }
                    },
                    onDelete: (id, title) async {
                      final confirmed = await _confirm(
                        context,
                        title: 'Ta bort länk',
                        message:
                            'Vill du ta bort länken "$title"?\n\nOriginalfilen i kursen påverkas inte.',
                        confirmLabel: 'Ta bort länk',
                      );
                      if (confirmed != true) return;
                      try {
                        await controller.deleteCourseLink(id);
                      } catch (error) {
                        if (!context.mounted) return;
                        _showErrorSnackBar(context, error);
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.primary,
    required this.isBusy,
    required this.onRefresh,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool primary;
  final bool isBusy;
  final Future<void> Function() onRefresh;
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
                tooltip: 'Uppdatera',
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
  const _HomeUploadsEmptyState();

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
            'Inga uppladdningar ännu.',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Ladda upp ljud eller video som bara ska användas i Home-spelaren.',
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
    required this.uploads,
    required this.disabled,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
  });

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
    required this.upload,
    required this.disabled,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
  });

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
      _showErrorSnackBar(context, 'Filnamn kan inte vara tomt.');
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
    final kind = widget.upload.kind.toLowerCase();
    final isVideo = kind.contains('video');
    final icon = isVideo ? Icons.videocam_outlined : Icons.headphones;
    final typeLabel = isVideo ? 'Video' : 'Ljud';
    final isDisabled = widget.disabled || _saving;
    final mediaAssetId = (widget.upload.mediaAssetId ?? '').trim();
    final mediaState = (widget.upload.mediaState ?? 'uploaded')
        .trim()
        .toLowerCase();
    final showsProcessing = mediaAssetId.isNotEmpty && mediaState != 'ready';
    final processingError = mediaState == 'failed';
    final processingLabel = processingError
        ? 'Bearbetningen misslyckades.'
        : 'Bearbetar ljud…';

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
              tooltip: 'Ta bort',
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
  const _CourseLinksEmptyState();

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
            'Inga länkar ännu.',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Länka in ljud/video från dina kurser. Tar du bort originalfilen blir länken ogiltig och kan inte spelas.',
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
    required this.links,
    required this.disabled,
    required this.onToggle,
    required this.onDelete,
  });

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
    required this.link,
    required this.disabled,
    required this.onToggle,
    required this.onDelete,
  });

  final HomePlayerCourseLinkItem link;
  final bool disabled;
  final Future<void> Function(String id, bool value) onToggle;
  final Future<void> Function(String id, String title) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = (link.kind ?? '').toLowerCase();
    final isVideo = kind.contains('video');
    final icon = isVideo ? Icons.videocam_outlined : Icons.headphones;
    final statusLabel = _statusLabel(link.status);
    final statusTone = _statusTone(link.status);
    final canToggle = link.status == HomePlayerCourseLinkStatus.active;
    final subtitleParts = <String>[
      if (link.courseTitle.isNotEmpty) 'Kurs: ${link.courseTitle}',
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
              tooltip: 'Ta bort länk',
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
        return 'Aktiv';
      case HomePlayerCourseLinkStatus.sourceMissing:
        return 'Källa saknas';
      case HomePlayerCourseLinkStatus.courseUnpublished:
        return 'Kurs ej publicerad';
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
          child: const Text('Avbryt'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

Future<void> _uploadHomeMedia(BuildContext context, WidgetRef ref) async {
  final picked = await pickMediaFile();
  if (picked == null) return;
  if (!context.mounted) return;

  final contentType = (picked.mimeType?.isNotEmpty ?? false)
      ? picked.mimeType!
      : _guessContentType(picked.name);
  final lower = contentType.toLowerCase();
  final filenameLower = picked.name.toLowerCase();
  final isWav =
      lower == 'audio/wav' ||
      lower == 'audio/x-wav' ||
      lower == 'audio/wave' ||
      lower == 'audio/vnd.wave' ||
      filenameLower.endsWith('.wav');
  final isMp4 = lower == 'video/mp4' || filenameLower.endsWith('.mp4');
  final isAudio = lower.startsWith('audio/') || isWav;
  final isVideo = lower.startsWith('video/') || isMp4;

  if (!(isAudio || isVideo)) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Välj en ljud- eller videofil.')),
    );
    return;
  }

  if (isAudio && !isWav) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Endast WAV stöds för ljud i Home Player.'),
      ),
    );
    return;
  }

  if (isVideo && !isMp4) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Endast MP4 stöds för video i Home Player.'),
      ),
    );
    return;
  }

  final suggested = _suggestTitleFromFilename(picked.name);
  final title = await _promptRequiredTitle(
    context,
    title: 'Namn på media',
    hint: 'T.ex. “Andningsövning”',
    initialValue: suggested,
    confirmLabel: 'Ladda upp',
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
    ),
  );

  if (ok == true && context.mounted) {
    ref.invalidate(homePlayerLibraryProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Uppladdning klar.')));
  }
}

Future<void> _linkFromCourses(BuildContext context, WidgetRef ref) async {
  final state = ref.read(homePlayerLibraryProvider).valueOrNull;
  final sources = state?.courseMedia ?? const <TeacherProfileLessonSource>[];
  if (sources.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Inga kursfiler hittades.')));
    return;
  }
  if (!context.mounted) return;

  final picked = await _pickCourseMedia(context, sources);
  if (picked == null) return;
  if (!context.mounted) return;

  final suggested = (picked.lessonTitle ?? '').trim();
  final title = await _promptRequiredTitle(
    context,
    title: 'Namn på länkad media',
    hint: 'T.ex. “Meditation – kväll”',
    initialValue: suggested.isNotEmpty ? suggested : 'Länkad media',
    confirmLabel: 'Skapa länk',
  );
  if (title == null) return;
  if (!context.mounted) return;

  final controller = ref.read(homePlayerLibraryProvider.notifier);
  try {
    await controller.createCourseLink(lessonMediaId: picked.id, title: title);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Länk skapad.')));
  } catch (error) {
    if (!context.mounted) return;
    _showErrorSnackBar(context, error);
  }
}

Future<String?> _promptRequiredTitle(
  BuildContext context, {
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
          child: const Text('Avbryt'),
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
) async {
  final audioVideo = sources
      .where((source) {
        final kind = source.kind.toLowerCase();
        final contentType = (source.contentType ?? '').toLowerCase();
        return kind.contains('audio') ||
            kind.contains('video') ||
            contentType.startsWith('audio/') ||
            contentType.startsWith('video/');
      })
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
                ? audioVideo
                : audioVideo
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
                    'Välj kursmedia att länka',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Sök på kurs eller lektion…',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final source = filtered[index];
                        final courseTitle = (source.courseTitle ?? '').trim();
                        final lessonTitle = (source.lessonTitle ?? '').trim();
                        final kind = source.kind.toLowerCase();
                        final isVideo = kind.contains('video');
                        final icon = isVideo
                            ? Icons.videocam_outlined
                            : Icons.headphones;
                        final subtitleParts = <String>[
                          if (courseTitle.isNotEmpty) courseTitle,
                          if (lessonTitle.isNotEmpty) 'Lektion: $lessonTitle',
                        ];
                        return ListTile(
                          leading: Icon(icon),
                          title: Text(
                            lessonTitle.isNotEmpty ? lessonTitle : 'Media',
                          ),
                          subtitle: subtitleParts.isEmpty
                              ? null
                              : Text(
                                  subtitleParts.join(' • '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => Navigator.of(sheetContext).pop(source),
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
  if (name.isEmpty) return 'Media';
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return name;
  return name.substring(0, dot);
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
