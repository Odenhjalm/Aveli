import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/home/application/home_audio_controller.dart';
import 'package:aveli/features/home/application/home_audio_session_controller.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/inline_audio_player.dart';

const double _homeAudioLogoColumnWidth = 92;
const double _homeAudioLogoColumnGap = 10;
const double _homeAudioTrackListInset =
    _homeAudioLogoColumnWidth + _homeAudioLogoColumnGap;

class HomeAudioSection extends ConsumerStatefulWidget {
  const HomeAudioSection({super.key});

  @override
  ConsumerState<HomeAudioSection> createState() => _HomeAudioSectionState();
}

class _HomeAudioSectionState extends ConsumerState<HomeAudioSection> {
  ProviderSubscription<AsyncValue<HomeAudioState>>? _audioSub;
  bool _trackListExpanded = false;

  @override
  void initState() {
    super.initState();
    _audioSub = ref.listenManual<AsyncValue<HomeAudioState>>(
      homeAudioProvider,
      (previous, next) {
        final snapshot = next.valueOrNull;
        if (snapshot == null) {
          return;
        }
        unawaited(
          ref
              .read(homeAudioSessionControllerProvider.notifier)
              .hydrateQueue(snapshot.items),
        );
      },
    );
    final initialSnapshot = ref.read(homeAudioProvider).valueOrNull;
    if (initialSnapshot != null) {
      unawaited(
        ref
            .read(homeAudioSessionControllerProvider.notifier)
            .hydrateQueue(initialSnapshot.items),
      );
    }
  }

  @override
  void dispose() {
    _audioSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(homeAudioProvider);
    final sessionState = ref.watch(homeAudioSessionControllerProvider);
    final logoProvider = ref
        .watch(backendAssetResolverProvider)
        .imageProvider('loggo_clean.png');
    final controller = ref.read(homeAudioSessionControllerProvider.notifier);

    if (!sessionState.hasQueue && asyncState.valueOrNull == null) {
      if (asyncState.isLoading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return _HomeAudioErrorCard(
        logoProvider: logoProvider,
        onRetry: () => ref.read(homeAudioProvider.notifier).refresh(),
      );
    }

    final queue = sessionState.queue;
    final selectedEntry = sessionState.currentEntry;
    final theme = Theme.of(context);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      opacity: 0.14,
      sigmaX: 5,
      sigmaY: 5,
      borderColor: theme.colorScheme.primary.withValues(alpha: 0.18),
      child: Column(
        key: const ValueKey('home-audio-section'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: _homeAudioLogoColumnWidth,
                child: Center(
                  child: SizedBox(
                    key: const ValueKey('home-audio-logo'),
                    width: _homeAudioLogoColumnWidth,
                    height: 72,
                    child: Image(
                      image: logoProvider,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: _homeAudioLogoColumnGap),
              Expanded(
                child: selectedEntry == null
                    ? const SizedBox(height: 34)
                    : InlineAudioPlayerView(
                        key: const ValueKey('home-audio-player-view'),
                        position: sessionState.position,
                        duration: sessionState.duration,
                        volume: sessionState.volume,
                        isPlaying: sessionState.isPlaying,
                        isInitializing: sessionState.isInitializing,
                        errorMessage: sessionState.errorMessage,
                        title: selectedEntry.title,
                        compact: true,
                        homePlayerUi: true,
                        onTogglePlayPause: () => controller.toggle(),
                        onSeek: (position) => controller.seek(position),
                        onVolumeChanged: (value) => controller.setVolume(value),
                      ),
              ),
              const SizedBox(width: 2),
              IconButton(
                key: const ValueKey('home-audio-track-list-toggle'),
                onPressed: queue.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _trackListExpanded = !_trackListExpanded;
                        });
                      },
                icon: Icon(
                  _trackListExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _trackListExpanded && queue.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(
                      top: 6,
                      left: _homeAudioTrackListInset,
                    ),
                    child: Container(
                      key: const ValueKey('home-audio-track-list'),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.06,
                          ),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final entry in queue) ...[
                            _HomeAudioTrackRow(
                              entry: entry,
                              selected:
                                  (selectedEntry?.index ?? -1) == entry.index,
                              onTap: () => controller.selectIndex(entry.index),
                            ),
                            if (entry != queue.last)
                              Divider(
                                height: 1,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.05,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey('home-audio-track-list-hidden'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HomeAudioErrorCard extends StatelessWidget {
  const _HomeAudioErrorCard({
    required this.logoProvider,
    required this.onRetry,
  });

  final ImageProvider<Object> logoProvider;
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
          SizedBox(
            height: 72,
            child: Image(image: logoProvider, fit: BoxFit.contain),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 20,
                color: theme.colorScheme.error.withValues(alpha: 0.82),
              ),
              const SizedBox(width: 12),
              IconButton(
                key: const ValueKey('home-audio-retry-button'),
                onPressed: onRetry,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeAudioTrackRow extends StatelessWidget {
  const _HomeAudioTrackRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final HomeAudioQueueEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: entry.title,
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('home-audio-track-${entry.index}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: selected
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
                  : Colors.transparent,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: theme.colorScheme.onSurface.withValues(
                      alpha: selected ? 0.90 : 0.72,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
