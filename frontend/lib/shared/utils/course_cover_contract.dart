import 'package:aveli/shared/utils/resolved_media_contract.dart';

class CourseCoverData extends ResolvedMediaData {
  const CourseCoverData({
    super.mediaId,
    required super.state,
    super.resolvedUrl,
  });

  factory CourseCoverData.fromJson(Map<String, dynamic> json) {
    return CourseCoverData(
      mediaId: json['media_id'] as String?,
      state: json['state'] as String,
      resolvedUrl: json['resolved_url'] as String?,
    );
  }
}
