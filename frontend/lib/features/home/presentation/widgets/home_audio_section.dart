import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/home/application/home_audio_controller.dart';
import 'package:aveli/features/home/data/home_audio_repository.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/inline_audio_player.dart';

const double _homeAudioLogoColumnWidth = 86;
const double _homeAudioLogoColumnGap = 10;
const double _homeAudioTrackListInset =
    _homeAudioLogoColumnWidth + _homeAudioLogoColumnGap;

class HomeAudioSection extends ConsumerStatefulWidget {
  const HomeAudioSection({super.key});

  @override
  ConsumerState<HomeAudioSection> createState() => _HomeAudioSectionState();
}

class _HomeAudioSectionState extends ConsumerState<HomeAudioSection> {
  String? _selectedMediaId;
  bool _trackListExpanded = false;
  InlineAudioPlayerVolumeState _volumeState =
      const InlineAudioPlayerVolumeState();

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(homeAudioProvider);
    final state = asyncState.valueOrNull;
    final logoProvider = ref
        .watch(backendAssetResolverProvider)
        .imageProvider('loggo_clean.png');

    if (state == null) {
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

    final readyItems = state.items
        .where((item) => item.isReady)
        .toList(growable: false);
    final selectedItem = _selectedItemFor(readyItems);
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
                child: Transform.translate(
                  offset: const Offset(0, -4),
                  child: SizedBox(
                    key: const ValueKey('home-audio-logo'),
                    height: 30,
                    child: Image(
                      image: logoProvider,
                      fit: BoxFit.contain,
                      alignment: Alignment.topLeft,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: _homeAudioLogoColumnGap),
              Expanded(
                child: selectedItem == null
                    ? const SizedBox(height: 34)
                    : InlineAudioPlayer(
                        key: ValueKey(
                          'home-audio-player-${selectedItem.media.mediaId ?? 'unknown'}',
                        ),
                        url: selectedItem.media.resolvedUrl!,
                        title: selectedItem.title,
                        compact: true,
                        homePlayerUi: true,
                        initialVolumeState: _volumeState,
                        onVolumeStateChanged: (nextState) {
                          setState(() {
                            _volumeState = nextState;
                          });
                        },
                      ),
              ),
              const SizedBox(width: 2),
              IconButton(
                key: const ValueKey('home-audio-track-list-toggle'),
                onPressed: readyItems.isEmpty
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
            child: _trackListExpanded && readyItems.isNotEmpty
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
                          for (final item in readyItems) ...[
                            _HomeAudioTrackRow(
                              item: item,
                              selected:
                                  (selectedItem?.media.mediaId ?? '') ==
                                  (item.media.mediaId ?? ''),
                              onTap: () {
                                final mediaId = item.media.mediaId;
                                if (mediaId == null || mediaId.isEmpty) {
                                  return;
                                }
                                setState(() {
                                  _selectedMediaId = mediaId;
                                });
                              },
                            ),
                            if (item != readyItems.last)
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

  HomeAudioFeedItem? _selectedItemFor(List<HomeAudioFeedItem> readyItems) {
    if (readyItems.isEmpty) {
      return null;
    }
    final selected = _selectedMediaId;
    if (selected == null || selected.isEmpty) {
      return readyItems.first;
    }
    for (final item in readyItems) {
      if (item.media.mediaId == selected) {
        return item;
      }
    }
    return readyItems.first;
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
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final HomeAudioFeedItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaId = item.media.mediaId ?? 'unknown';
    return Semantics(
      label: item.title,
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('home-audio-track-$mediaId'),
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
                  item.title,
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
