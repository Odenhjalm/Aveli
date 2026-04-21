import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/features/home/application/home_audio_controller.dart';
import 'package:aveli/features/home/data/home_audio_repository.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/inline_audio_player.dart';

class HomeAudioSection extends ConsumerStatefulWidget {
  const HomeAudioSection({super.key});

  @override
  ConsumerState<HomeAudioSection> createState() => _HomeAudioSectionState();
}

class _HomeAudioSectionState extends ConsumerState<HomeAudioSection> {
  String? _expandedMediaId;

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(homeAudioProvider);
    final state = asyncState.valueOrNull;

    if (state == null) {
      if (asyncState.isLoading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return _HomeAudioErrorCard(
        message: _backendOwnedHomeAudioMessage(asyncState.error),
        onRetry: () => ref.read(homeAudioProvider.notifier).refresh(),
      );
    }

    final texts = state.textBundle;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      opacity: 0.14,
      sigmaX: 5,
      sigmaY: 5,
      borderColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.18),
      child: Column(
        key: const ValueKey('home-audio-section'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      texts.requireValue('home.audio.section_title'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      texts.requireValue('home.audio.section_description'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: texts.requireValue('home.audio.retry_action'),
                onPressed: () => ref.read(homeAudioProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (state.items.isEmpty)
            _HomeAudioEmptyState(texts: texts)
          else
            Column(
              children: [
                for (final item in state.items) ...[
                  _HomeAudioItemCard(
                    item: item,
                    texts: texts,
                    expanded: _expandedMediaId == (item.media.mediaId ?? ''),
                    onToggleExpanded: item.isReady
                        ? () {
                            final mediaId = item.media.mediaId ?? '';
                            if (mediaId.isEmpty) {
                              return;
                            }
                            setState(() {
                              _expandedMediaId = _expandedMediaId == mediaId
                                  ? null
                                  : mediaId;
                            });
                          }
                        : null,
                  ),
                  if (item != state.items.last) const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _HomeAudioErrorCard extends StatelessWidget {
  const _HomeAudioErrorCard({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      opacity: 0.14,
      sigmaX: 5,
      sigmaY: 5,
      borderColor: theme.colorScheme.error.withValues(alpha: 0.18),
      child: Column(
        key: const ValueKey('home-audio-error'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 36, color: theme.colorScheme.error),
          if ((message ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh)),
        ],
      ),
    );
  }
}

class _HomeAudioEmptyState extends StatelessWidget {
  const _HomeAudioEmptyState({required this.texts});

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
            size: 44,
            color: theme.colorScheme.primary.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 10),
          Text(
            texts.requireValue('home.audio.empty_title'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            texts.requireValue('home.audio.empty_status'),
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

class _HomeAudioItemCard extends StatelessWidget {
  const _HomeAudioItemCard({
    required this.item,
    required this.texts,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final HomeAudioFeedItem item;
  final HomePlayerTextBundle texts;
  final bool expanded;
  final VoidCallback? onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaId = item.media.mediaId ?? 'unknown';
    return Container(
      key: ValueKey('home-audio-item-$mediaId'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: 0.12,
                ),
                child: Icon(
                  item.sourceType == HomeAudioSourceType.directUpload
                      ? Icons.person_outline
                      : Icons.menu_book_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if ((item.lessonTitle ?? '').isNotEmpty)
                      Text(
                        item.lessonTitle!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    if ((item.courseTitle ?? '').isNotEmpty)
                      Text(
                        item.courseTitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (item.isReady)
                IconButton(
                  tooltip: texts.requireValue('home.audio.ready_status'),
                  onPressed: onToggleExpanded,
                  icon: Icon(
                    expanded
                        ? Icons.expand_less_outlined
                        : Icons.play_circle_outline,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(
                label: item.sourceType == HomeAudioSourceType.directUpload
                    ? texts.requireValue('home.audio.direct_upload_label')
                    : texts.requireValue('home.audio.course_link_label'),
                background: theme.colorScheme.primary.withValues(alpha: 0.12),
                foreground: theme.colorScheme.primary,
              ),
              _StatusChip(
                label: _statusText(item, texts),
                background: _statusBackground(theme, item),
                foreground: _statusForeground(theme, item),
              ),
            ],
          ),
          if (expanded && item.isReady) ...[
            const SizedBox(height: 14),
            InlineAudioPlayer(
              key: ValueKey('home-audio-player-$mediaId'),
              url: item.media.resolvedUrl!,
              title: item.title,
              compact: true,
              minimalUi: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _statusText(HomeAudioFeedItem item, HomePlayerTextBundle texts) {
  final state = item.media.state.trim().toLowerCase();
  switch (state) {
    case 'ready':
      return texts.requireValue('home.audio.ready_status');
    case 'failed':
      return texts.requireValue('home.audio.failed_error');
    case 'pending_upload':
      return texts.requireValue('home.audio.pending_status');
    case 'uploaded':
    case 'processing':
      return texts.requireValue('home.audio.processing_status');
    default:
      return texts.requireValue('home.audio.processing_status');
  }
}

Color _statusBackground(ThemeData theme, HomeAudioFeedItem item) {
  final state = item.media.state.trim().toLowerCase();
  switch (state) {
    case 'ready':
      return theme.colorScheme.secondary.withValues(alpha: 0.18);
    case 'failed':
      return theme.colorScheme.error.withValues(alpha: 0.14);
    default:
      return theme.colorScheme.tertiary.withValues(alpha: 0.14);
  }
}

Color _statusForeground(ThemeData theme, HomeAudioFeedItem item) {
  final state = item.media.state.trim().toLowerCase();
  switch (state) {
    case 'ready':
      return theme.colorScheme.secondary;
    case 'failed':
      return theme.colorScheme.error;
    default:
      return theme.colorScheme.tertiary;
  }
}

String? _backendOwnedHomeAudioMessage(Object? error) {
  if (error == null) {
    return null;
  }
  final failure = AppFailure.from(error);
  final message = failure.message.trim();
  if (failure.code != null && message.isNotEmpty) {
    return message;
  }
  return null;
}
