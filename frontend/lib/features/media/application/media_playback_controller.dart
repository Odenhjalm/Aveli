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
  });

  final String? currentMediaId;
  final bool isPlaying;
  final MediaPlaybackType? mediaType;
  final String? url;
  final String? title;
  final Duration? durationHint;
  final bool isLoading;
  final String? errorMessage;

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

    // Safety: metadata changes (e.g. renaming a title) must never interrupt
    // playback or force a re-init when the media identity is unchanged.
    if (state.isPlaying && state.currentMediaId == trimmedId) {
      if (state.isLoading) {
        stop();
        return;
      }
      final trimmedTitle = title?.trim();
      if ((trimmedTitle ?? '').isNotEmpty || durationHint != null) {
        state = state.copyWith(title: trimmedTitle, durationHint: durationHint);
      }
      return;
    }

    final token = ++_requestToken;

    state = MediaPlaybackState(
      currentMediaId: trimmedId,
      isPlaying: true,
      mediaType: mediaType,
      url: url?.trim(),
      title: title?.trim(),
      durationHint: durationHint,
      isLoading: (url ?? '').trim().isEmpty,
      errorMessage: null,
    );

    if (!state.isLoading) return;

    if (urlLoader == null) {
      stop();
      return;
    }

    try {
      final loadedUrl = (await urlLoader()).trim();
      if (_disposed || token != _requestToken) return;
      if (loadedUrl.isEmpty) {
        throw StateError('Empty playback URL');
      }
      state = state.copyWith(url: loadedUrl, isLoading: false);
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
