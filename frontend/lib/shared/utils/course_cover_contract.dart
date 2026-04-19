import 'package:aveli/shared/utils/resolved_media_contract.dart';

class CourseCoverData extends ResolvedMediaData {
  const CourseCoverData({
    required super.mediaId,
    required super.state,
    required super.resolvedUrl,
  });

  factory CourseCoverData.fromJson(Map<String, dynamic> json) {
    final mediaId = json['media_id'];
    final state = json['state'];
    final resolvedUrl = json['resolved_url'];
    if (mediaId is! String || mediaId.trim().isEmpty) {
      throw StateError('Invalid course cover media_id');
    }
    if (state != 'ready') {
      throw StateError('Invalid course cover state');
    }
    if (resolvedUrl is! String || resolvedUrl.trim().isEmpty) {
      throw StateError('Invalid course cover resolved_url');
    }
    return CourseCoverData(
      mediaId: mediaId.trim(),
      state: state,
      resolvedUrl: resolvedUrl.trim(),
    );
  }
}
