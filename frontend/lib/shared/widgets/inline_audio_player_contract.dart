import 'package:flutter/foundation.dart';

@immutable
class InlineAudioPlaybackSource {
  const InlineAudioPlaybackSource({required this.url, this.expiresAt});

  final String url;
  final DateTime? expiresAt;
}

@immutable
class InlineAudioPlayerVolumeState {
  const InlineAudioPlayerVolumeState({
    this.volume = 1.0,
    this.lastVolume = 1.0,
  });

  final double volume;
  final double lastVolume;

  @override
  bool operator ==(Object other) {
    return other is InlineAudioPlayerVolumeState &&
        other.volume == volume &&
        other.lastVolume == lastVolume;
  }

  @override
  int get hashCode => Object.hash(volume, lastVolume);
}
