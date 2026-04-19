import 'package:aveli/shared/utils/resolved_media_contract.dart';

const Set<String> _courseCoverFields = <String>{
  'media_id',
  'state',
  'resolved_url',
};

class CourseCoverData extends ResolvedMediaData {
  const CourseCoverData({
    required super.mediaId,
    required super.state,
    required super.resolvedUrl,
  });

  factory CourseCoverData.fromJson(Map<String, dynamic> json) {
    final extraFields = json.keys
        .where((key) => !_courseCoverFields.contains(key))
        .toList(growable: false);
    if (extraFields.isNotEmpty) {
      throw StateError('Invalid course cover fields');
    }
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

  bool get hasRenderableCover =>
      state == 'ready' && (resolvedUrl?.trim().isNotEmpty ?? false);
}

String? courseCoverResolvedUrl(CourseCoverData? cover) {
  if (cover == null) return null;
  if (!cover.hasRenderableCover) {
    throw StateError('Invalid course cover render state');
  }
  return cover.resolvedUrl!.trim();
}
