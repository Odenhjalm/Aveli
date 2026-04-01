import 'package:flutter/foundation.dart';

@immutable
class CourseCoverData {
  const CourseCoverData({
    this.mediaId,
    required this.state,
    this.resolvedUrl,
    required this.source,
  });

  final String? mediaId;
  final String state;
  final String? resolvedUrl;
  final String source;

  factory CourseCoverData.fromJson(Map<String, dynamic> json) {
    return CourseCoverData(
      mediaId: json['media_id'] as String?,
      state: json['state'] as String,
      resolvedUrl: json['resolved_url'] as String?,
      source: json['source'] as String,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'media_id': mediaId,
    'state': state,
    'resolved_url': resolvedUrl,
    'source': source,
  };
}
