import 'dart:convert';

enum WavUploadFailureKind { cancelled, expired, failed }

class WavUploadFailure implements Exception {
  const WavUploadFailure(this.kind, {this.detail});

  final WavUploadFailureKind kind;
  final String? detail;

  @override
  String toString() => 'WavUploadFailure($kind)';
}

class WavUploadCancelToken {
  bool _cancelled = false;
  final List<void Function()> _callbacks = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final cb in List<void Function()>.from(_callbacks)) {
      cb();
    }
    _callbacks.clear();
  }

  void onCancel(void Function() callback) {
    if (_cancelled) {
      callback();
      return;
    }
    _callbacks.add(callback);
  }
}

String wavUploadFingerprint({
  required String fileName,
  required int size,
  required int? lastModified,
}) {
  final raw = '$fileName|$size|${lastModified ?? 0}';
  return base64Url.encode(utf8.encode(raw));
}

class WavResumableSession {
  const WavResumableSession({
    required this.mediaId,
    required this.courseId,
    required this.lessonId,
    required this.sessionUrl,
    required this.token,
    required this.bucket,
    required this.objectPath,
    required this.contentType,
    required this.size,
    required this.fileName,
    required this.fingerprint,
    required this.upsert,
    this.cacheControl,
    this.lastModified,
    this.offset = 0,
    this.expiresAt,
    this.createdAt,
  });

  final String mediaId;
  final String courseId;
  final String lessonId;
  final Uri sessionUrl;
  final String token;
  final String bucket;
  final String objectPath;
  final String contentType;
  final int size;
  final String fileName;
  final String fingerprint;
  final bool upsert;
  final String? cacheControl;
  final int? lastModified;
  final int offset;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  WavResumableSession copyWith({
    int? offset,
    DateTime? expiresAt,
  }) {
    return WavResumableSession(
      mediaId: mediaId,
      courseId: courseId,
      lessonId: lessonId,
      sessionUrl: sessionUrl,
      token: token,
      bucket: bucket,
      objectPath: objectPath,
      contentType: contentType,
      size: size,
      fileName: fileName,
      fingerprint: fingerprint,
      upsert: upsert,
      cacheControl: cacheControl,
      lastModified: lastModified,
      offset: offset ?? this.offset,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mediaId': mediaId,
      'courseId': courseId,
      'lessonId': lessonId,
      'sessionUrl': sessionUrl.toString(),
      'token': token,
      'bucket': bucket,
      'objectPath': objectPath,
      'contentType': contentType,
      'size': size,
      'fileName': fileName,
      'fingerprint': fingerprint,
      'upsert': upsert,
      'cacheControl': cacheControl,
      'lastModified': lastModified,
      'offset': offset,
      'expiresAt': expiresAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  static WavResumableSession? fromJson(Map<String, dynamic> json) {
    try {
      final sessionUrl = Uri.parse(json['sessionUrl'] as String);
      final expiresAtRaw = json['expiresAt'] as String?;
      final createdAtRaw = json['createdAt'] as String?;
      final size = (json['size'] as num?)?.toInt() ?? 0;
      final offset = (json['offset'] as num?)?.toInt() ?? 0;
      final lastModified = (json['lastModified'] as num?)?.toInt();
      final fileName = json['fileName'] as String;
      final fingerprintRaw = json['fingerprint'] as String?;
      final fingerprint = (fingerprintRaw != null && fingerprintRaw.isNotEmpty)
          ? fingerprintRaw
          : wavUploadFingerprint(
              fileName: fileName,
              size: size,
              lastModified: lastModified,
            );
      return WavResumableSession(
        mediaId: json['mediaId'] as String,
        courseId: json['courseId'] as String,
        lessonId: json['lessonId'] as String,
        sessionUrl: sessionUrl,
        token: json['token'] as String,
        bucket: json['bucket'] as String,
        objectPath: json['objectPath'] as String,
        contentType: json['contentType'] as String,
        size: size,
        fileName: fileName,
        fingerprint: fingerprint,
        upsert: json['upsert'] == true,
        cacheControl: json['cacheControl'] as String?,
        lastModified: lastModified,
        offset: offset,
        expiresAt: expiresAtRaw == null ? null : DateTime.tryParse(expiresAtRaw),
        createdAt: createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw),
      );
    } catch (_) {
      return null;
    }
  }

  String toStoragePayload() => jsonEncode(toJson());

  static WavResumableSession? fromStoragePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return WavResumableSession.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Map<String, String> resumableHeaders() {
    final headers = <String, String>{
      'x-upsert': upsert ? 'true' : 'false',
    };
    if (cacheControl != null && cacheControl!.isNotEmpty) {
      headers['cache-control'] = cacheControl!;
    }
    return headers;
  }
}
