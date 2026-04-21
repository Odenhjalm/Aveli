enum HomePlayerUploadRoute {
  wavPipeline,
  directMp3,
  directM4a,
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

const _mp3MimeTypes = <String>{'audio/mpeg', 'audio/mp3'};
const _m4aMimeTypes = <String>{'audio/m4a', 'audio/mp4'};

HomePlayerUploadRoute detectHomePlayerUploadRoute({
  required String mimeType,
  required String filename,
}) {
  final lowerMime = mimeType.trim().toLowerCase();
  final filenameLower = filename.trim().toLowerCase();

  final isWav =
      _wavMimeTypes.contains(lowerMime) || filenameLower.endsWith('.wav');
  if (isWav) return HomePlayerUploadRoute.wavPipeline;

  final isMp3 =
      _mp3MimeTypes.contains(lowerMime) || filenameLower.endsWith('.mp3');
  if (isMp3) return HomePlayerUploadRoute.directMp3;

  final isM4a =
      _m4aMimeTypes.contains(lowerMime) || filenameLower.endsWith('.m4a');
  if (isM4a) return HomePlayerUploadRoute.directM4a;

  if (lowerMime.startsWith('audio/')) {
    return HomePlayerUploadRoute.unsupportedAudio;
  }
  if (lowerMime.startsWith('video/')) {
    return HomePlayerUploadRoute.unsupportedVideo;
  }
  if (filenameLower.endsWith('.mp4') ||
      filenameLower.endsWith('.mov') ||
      filenameLower.endsWith('.m4v') ||
      filenameLower.endsWith('.webm') ||
      filenameLower.endsWith('.mkv')) {
    return HomePlayerUploadRoute.unsupportedVideo;
  }
  return HomePlayerUploadRoute.unsupportedOther;
}

String homePlayerUploadNormalizedMimeType(HomePlayerUploadRoute route) {
  switch (route) {
    case HomePlayerUploadRoute.wavPipeline:
      return 'audio/wav';
    case HomePlayerUploadRoute.directMp3:
      return 'audio/mpeg';
    case HomePlayerUploadRoute.directM4a:
      return 'audio/m4a';
    case HomePlayerUploadRoute.unsupportedAudio:
    case HomePlayerUploadRoute.unsupportedVideo:
    case HomePlayerUploadRoute.unsupportedOther:
      return '';
  }
}

String? homePlayerUploadUnsupportedTextId(HomePlayerUploadRoute route) {
  switch (route) {
    case HomePlayerUploadRoute.unsupportedAudio:
      return 'home.player_upload.unsupported_audio_error';
    case HomePlayerUploadRoute.unsupportedVideo:
      return 'home.player_upload.unsupported_video_error';
    case HomePlayerUploadRoute.unsupportedOther:
      return 'home.player_upload.unsupported_other_error';
    case HomePlayerUploadRoute.wavPipeline:
    case HomePlayerUploadRoute.directMp3:
    case HomePlayerUploadRoute.directM4a:
      return null;
  }
}
