import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum MediaPlaybackType { audio, video }

class MediaPlaybackState {
  const MediaPlaybackState({
    this.currentMediaId,
    this.isPlaying = false,
    this.mediaType,
    this.url,
    this.title,
    this.durationHint,
    this.isLoading = false,
    this.errorMessage,
    this.sourceRevision = 0,
  });

  final String? currentMediaId;
  final bool isPlaying;
  final MediaPlaybackType? mediaType;
  final String? url;
  final String? title;
  final Duration? durationHint;
  final bool isLoading;
  final String? errorMessage;
  final int sourceRevision;

  bool get hasActiveMedia =>
      isPlaying && (currentMediaId ?? '').trim().isNotEmpty;

  MediaPlaybackState copyWith({
    String? currentMediaId,
    bool? isPlaying,
    MediaPlaybackType? mediaType,
    String? url,
    String? title,
    Duration? durationHint,
    bool? isLoading,
    String? errorMessage,
    int? sourceRevision,
  }) {
    return MediaPlaybackState(
      currentMediaId: currentMediaId ?? this.currentMediaId,
      isPlaying: isPlaying ?? this.isPlaying,
      mediaType: mediaType ?? this.mediaType,
      url: url ?? this.url,
      title: title ?? this.title,
      durationHint: durationHint ?? this.durationHint,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      sourceRevision: sourceRevision ?? this.sourceRevision,
    );
  }
}

class MediaPlaybackController extends AutoDisposeNotifier<MediaPlaybackState> {
  int _requestToken = 0;
  bool _disposed = false;

  @override
  MediaPlaybackState build() {
    ref.onDispose(() => _disposed = true);
    return const MediaPlaybackState();
  }

  void updateTitleIfActive(String mediaId, String title) {
    if (_disposed) return;
    final trimmedId = mediaId.trim();
    final trimmedTitle = title.trim();
    if (trimmedId.isEmpty || trimmedTitle.isEmpty) return;
    if (!state.isPlaying || state.currentMediaId != trimmedId) return;
    state = state.copyWith(title: trimmedTitle);
  }

  Future<void> play({
    required String mediaId,
    required MediaPlaybackType mediaType,
    String? url,
    Future<String> Function()? urlLoader,
    String? title,
    Duration? durationHint,
  }) async {
    final trimmedId = mediaId.trim();
    if (trimmedId.isEmpty) return;

    final trimmedUrl = url?.trim();
    final hasUrl = (trimmedUrl ?? '').isNotEmpty;
    final trimmedTitle = title?.trim();
    final nextTitle = (trimmedTitle ?? '').isNotEmpty ? trimmedTitle : null;
    final isSameMedia = state.currentMediaId == trimmedId;

    // Separate concerns:
    // - media identity: currentMediaId
    // - metadata: title/durationHint
    // - playback source: url/urlLoader
    //
    // IMPORTANT: A feed reload may re-apply the same media id with a new URL.
    // Never skip source binding just because the id is unchanged.
    if (isSameMedia) {
      if (hasUrl) {
        state = state.copyWith(
          currentMediaId: trimmedId,
          isPlaying: true,
          mediaType: mediaType,
          url: trimmedUrl,
          title: nextTitle,
          durationHint: durationHint,
          isLoading: false,
          sourceRevision: state.sourceRevision + 1,
        );
        return;
      }

      if (urlLoader != null) {
        final token = ++_requestToken;
        state = state.copyWith(
          currentMediaId: trimmedId,
          isPlaying: true,
          mediaType: mediaType,
          title: nextTitle,
          durationHint: durationHint,
          isLoading: true,
        );

        try {
          final loadedUrl = (await urlLoader()).trim();
          if (_disposed || token != _requestToken) return;
          if (loadedUrl.isEmpty) {
            throw StateError('Empty playback URL');
          }
          state = state.copyWith(
            url: loadedUrl,
            isLoading: false,
            sourceRevision: state.sourceRevision + 1,
          );
        } catch (error) {
          if (_disposed || token != _requestToken) return;
          if (kDebugMode) {
            debugPrint(
              '[media_playback] failed to refresh source for mediaId=$trimmedId: $error',
            );
          }
          state = state.copyWith(
            isLoading: false,
            errorMessage: error.toString(),
          );
          return;
        }
        return;
      }

      if (nextTitle != null ||
          durationHint != null ||
          state.mediaType != mediaType) {
        state = state.copyWith(
          mediaType: mediaType,
          title: nextTitle,
          durationHint: durationHint,
        );
      }
      return;
    }

    final token = ++_requestToken;

    state = MediaPlaybackState(
      currentMediaId: trimmedId,
      isPlaying: true,
      mediaType: mediaType,
      url: hasUrl ? trimmedUrl : null,
      title: trimmedTitle,
      durationHint: durationHint,
      isLoading: !hasUrl,
      errorMessage: null,
      sourceRevision: state.sourceRevision + 1,
    );

    if (!state.isLoading) return;

    if (urlLoader == null) {
      if (kDebugMode) {
        debugPrint(
          '[media_playback] refusing to play mediaId=$trimmedId: empty url and no urlLoader',
        );
      }
      stop();
      return;
    }

    try {
      final loadedUrl = (await urlLoader()).trim();
      if (_disposed || token != _requestToken) return;
      if (loadedUrl.isEmpty) {
        throw StateError('Empty playback URL');
      }
      state = state.copyWith(
        url: loadedUrl,
        isLoading: false,
        sourceRevision: state.sourceRevision + 1,
      );
    } catch (error) {
      if (_disposed || token != _requestToken) return;
      stop();
      rethrow;
    }
  }

  void stop() {
    _requestToken++;
    if (_disposed) return;
    state = const MediaPlaybackState();
  }
}

final mediaPlaybackControllerProvider =
    AutoDisposeNotifierProvider<MediaPlaybackController, MediaPlaybackState>(
      MediaPlaybackController.new,
    );
