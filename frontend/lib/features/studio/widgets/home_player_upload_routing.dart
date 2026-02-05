enum HomePlayerUploadRoute {
  wavPipeline,
  directMp3,
  directMp4,
  unsupportedAudio,
  unsupportedVideo,
  unsupportedOther,
}

const _wavMimeTypes = <String>{
  'audio/wav',
  'audio/x-wav',
  'audio/wave',
  'audio/vnd.wave',
};

const _mp3MimeTypes = <String>{
  'audio/mpeg',
  'audio/mp3',
};

HomePlayerUploadRoute detectHomePlayerUploadRoute({
  required String mimeType,
  required String filename,
}) {
  final lowerMime = mimeType.trim().toLowerCase();
  final filenameLower = filename.trim().toLowerCase();

  final isWav = _wavMimeTypes.contains(lowerMime) || filenameLower.endsWith('.wav');
  if (isWav) return HomePlayerUploadRoute.wavPipeline;

  final isMp3 = _mp3MimeTypes.contains(lowerMime) || filenameLower.endsWith('.mp3');
  if (isMp3) return HomePlayerUploadRoute.directMp3;

  final isMp4 = lowerMime == 'video/mp4' || filenameLower.endsWith('.mp4');
  if (isMp4) return HomePlayerUploadRoute.directMp4;

  if (lowerMime.startsWith('audio/')) return HomePlayerUploadRoute.unsupportedAudio;
  if (lowerMime.startsWith('video/')) return HomePlayerUploadRoute.unsupportedVideo;
  return HomePlayerUploadRoute.unsupportedOther;
}

String homePlayerUploadNormalizedMimeType(HomePlayerUploadRoute route) {
  switch (route) {
    case HomePlayerUploadRoute.wavPipeline:
      return 'audio/wav';
    case HomePlayerUploadRoute.directMp3:
      return 'audio/mpeg';
    case HomePlayerUploadRoute.directMp4:
      return 'video/mp4';
    case HomePlayerUploadRoute.unsupportedAudio:
    case HomePlayerUploadRoute.unsupportedVideo:
    case HomePlayerUploadRoute.unsupportedOther:
      return '';
  }
}

String homePlayerUploadUnsupportedMessage(HomePlayerUploadRoute route) {
  switch (route) {
    case HomePlayerUploadRoute.unsupportedAudio:
      return 'Endast WAV eller MP3 stöds för ljud i Home Player.';
    case HomePlayerUploadRoute.unsupportedVideo:
      return 'Endast MP4 stöds för video i Home Player.';
    case HomePlayerUploadRoute.unsupportedOther:
      return 'Välj en WAV-, MP3- eller MP4-fil.';
    case HomePlayerUploadRoute.wavPipeline:
    case HomePlayerUploadRoute.directMp3:
    case HomePlayerUploadRoute.directMp4:
      return '';
  }
}

