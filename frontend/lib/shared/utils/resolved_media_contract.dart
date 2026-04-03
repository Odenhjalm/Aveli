import 'package:flutter/foundation.dart';

@immutable
class ResolvedMediaData {
  const ResolvedMediaData({
    this.mediaId,
    required this.state,
    this.resolvedUrl,
  });

  final String? mediaId;
  final String state;
  final String? resolvedUrl;

  factory ResolvedMediaData.fromJson(Map<String, dynamic> json) {
    return ResolvedMediaData(
      mediaId: json['media_id'] as String?,
      state: json['state'] as String,
      resolvedUrl: json['resolved_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'media_id': mediaId,
    'state': state,
    'resolved_url': resolvedUrl,
  };
}
