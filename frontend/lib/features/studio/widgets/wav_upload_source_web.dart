// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'wav_upload_types.dart';

const String _tusVersion = '1.0.0';
const int _chunkSize = 6 * 1024 * 1024; // Supabase requires 6MB chunks.
const int _fingerprintMaxBytes = 4 * 1024 * 1024;
const int _maxSigningRefreshAttempts = 3;
const String _storageKeyPrefix = 'aveli.wavUpload.';

class WavUploadFile {
  WavUploadFile(this.file);

  final File file;
  String? _contentFingerprint;

  String get name => file.name;
  int get size => file.size;
  String? get mimeType => file.type.isEmpty ? null : file.type;
  int? get lastModified => file.lastModified;

  Future<String> contentFingerprint() async {
    if (_contentFingerprint != null) return _contentFingerprint!;
    final slice = file.slice(0, math.min(size, _fingerprintMaxBytes));
    final hash = await _hashBlob(slice);
    _contentFingerprint = wavUploadFingerprint(
      fileName: name,
      size: size,
      contentHash: hash,
    );
    return _contentFingerprint!;
  }
}

Future<WavUploadFile?> pickWavFile() async {
  final input = FileUploadInputElement()
    ..accept = '.wav,audio/wav,audio/x-wav'
    ..multiple = false;

  final completer = Completer<WavUploadFile?>();

  input.onChange.first.then((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      input.remove();
      return;
    }
    completer.complete(WavUploadFile(files.first));
    input.remove();
  });

  document.body?.append(input);
  input
    ..style.display = 'none'
    ..value = ''
    ..click();

  return completer.future.timeout(
    const Duration(minutes: 5),
    onTimeout: () => null,
  );
}

Future<WavResumableSession?> findResumableSession({
  required String courseId,
  required String lessonId,
  required WavUploadFile file,
}) async {
  try {
    final fingerprint = await file.contentFingerprint();
    final session = _loadSession(_sessionKey(courseId, lessonId, fingerprint));
    if (session == null) return null;

    if (session.courseId != courseId || session.lessonId != lessonId) {
      return null;
    }
    if (session.fingerprint != fingerprint) {
      return null;
    }
    return session;
  } catch (_) {
    return null;
  }
}

void clearResumableSession(WavResumableSession session) {
  _clearSession(session);
}

// Verification (manual):
// 1) Start >=500 MB WAV upload in web app.
// 2) Let it reach ~20–40%.
// 3) Close tab.
// 4) Reopen app and click "Byt WAV".
// 5) Select the same WAV.
// 6) Confirm HEAD -> PATCH resume (no new POST).
// 7) Let upload finish; verify storage.objects row exists.
// 8) Confirm media_assets: uploaded -> processing -> ready; MP3 plays.
Future<void> uploadWavFile({
  required String mediaId,
  required String courseId,
  required String lessonId,
  required Uri uploadUrl,
  required String objectPath,
  required Map<String, String> headers,
  required WavUploadFile file,
  required String contentType,
  required void Function(int sent, int total) onProgress,
  WavUploadCancelToken? cancelToken,
  void Function(bool resumed)? onResume,
  Future<bool> Function()? ensureAuth,
  Future<WavUploadSigningRefresh> Function(WavResumableSession session)?
      refreshSigning,
  void Function()? onSigningRefresh,
  WavResumableSession? resumableSession,
}) async {
  if (cancelToken?.isCancelled == true) {
    throw const WavUploadFailure(WavUploadFailureKind.cancelled);
  }

  WavResumableSession? session;

  try {
    session = resumableSession ??
        await _createResumableSession(
          mediaId: mediaId,
          courseId: courseId,
          lessonId: lessonId,
          uploadUrl: uploadUrl,
          objectPath: objectPath,
          headers: headers,
          file: file,
          contentType: contentType,
        );

    final resumed = resumableSession != null;
    onResume?.call(resumed);

    var tusHeaders = _baseTusHeaders(session!);
    var signingRefreshAttempts = 0;

    Future<void> refreshSigningToken() async {
      if (cancelToken?.isCancelled == true) {
        throw const WavUploadFailure(WavUploadFailureKind.cancelled);
      }
      if (session == null) {
        throw const WavUploadFailure(WavUploadFailureKind.failed);
      }

      final authEnsurer = ensureAuth;
      if (authEnsurer != null) {
        final ok = await authEnsurer();
        if (!ok) {
          throw const WavUploadFailure(WavUploadFailureKind.expired);
        }
      }

      final refresher = refreshSigning;
      if (refresher == null) {
        throw const WavUploadFailure(WavUploadFailureKind.expired);
      }
      if (signingRefreshAttempts >= _maxSigningRefreshAttempts) {
        throw const WavUploadFailure(WavUploadFailureKind.failed);
      }
      signingRefreshAttempts += 1;
      onSigningRefresh?.call();

      final refreshed = await refresher(session!);
      final signedInfo = _parseSignedUploadInfo(refreshed.uploadUrl);
      final normalizedPath =
          _normalizeObjectPath(signedInfo.bucket, refreshed.objectPath);
      if (signedInfo.bucket != session!.bucket) {
        throw const WavUploadFailure(WavUploadFailureKind.failed);
      }
      if (normalizedPath != session!.objectPath) {
        throw const WavUploadFailure(WavUploadFailureKind.failed);
      }

      session = session!.copyWith(
        token: signedInfo.token,
        expiresAt: refreshed.expiresAt.toUtc(),
      );
      _storeSession(session!);
      tusHeaders = _baseTusHeaders(session!);
      onResume?.call(true);
    }

    Future<int> fetchOffsetWithRefresh() async {
      while (true) {
        try {
          final offset = await _fetchOffset(
            session!.sessionUrl,
            tusHeaders,
            cancelToken: cancelToken,
          );
          signingRefreshAttempts = 0;
          return offset;
        } on WavUploadFailure catch (error) {
          if (error.kind != WavUploadFailureKind.expired) rethrow;
          await refreshSigningToken();
        }
      }
    }

    Future<int> uploadChunkWithRefresh(Blob chunk, int offset) async {
      while (true) {
        try {
          final nextOffset = await _uploadChunkWithRetry(
            session!.sessionUrl,
            chunk,
            offset,
            tusHeaders,
            cancelToken: cancelToken,
          );
          signingRefreshAttempts = 0;
          return nextOffset;
        } on WavUploadFailure catch (error) {
          if (error.kind != WavUploadFailureKind.expired) rethrow;
          await refreshSigningToken();
          return await fetchOffsetWithRefresh();
        }
      }
    }

    var offset = await fetchOffsetWithRefresh();
    if (offset < 0) offset = 0;
    if (offset != session!.offset) {
      session = session!.copyWith(offset: offset);
      _storeSession(session!);
    }
    onProgress(offset, file.size);

    while (offset < file.size) {
      if (cancelToken?.isCancelled == true) {
        _clearSession(session!);
        throw const WavUploadFailure(WavUploadFailureKind.cancelled);
      }

      final end = math.min(offset + _chunkSize, file.size);
      final chunk = file.file.slice(offset, end);

      final nextOffset = await uploadChunkWithRefresh(chunk, offset);

      if (nextOffset <= offset) {
        offset = await fetchOffsetWithRefresh();
      } else {
        offset = nextOffset;
      }

      session = session!.copyWith(offset: offset);
      _storeSession(session!);
      onProgress(offset, file.size);
    }

    _clearSession(session!);
  } on WavUploadFailure catch (error) {
    if (session != null && error.kind == WavUploadFailureKind.cancelled) {
      _clearSession(session!);
    }
    rethrow;
  }
}

class _SignedUploadInfo {
  _SignedUploadInfo({
    required this.storageBaseUrl,
    required this.bucket,
    required this.token,
  });

  final Uri storageBaseUrl;
  final String bucket;
  final String token;
}

String _sessionKey(String courseId, String lessonId, String fingerprint) {
  return '$_storageKeyPrefix$courseId.$lessonId.$fingerprint';
}

WavResumableSession? _loadSession(String key) {
  final raw = window.localStorage[key];
  if (raw == null || raw.isEmpty) return null;
  return WavResumableSession.fromStoragePayload(raw);
}

void _storeSession(WavResumableSession session) {
  try {
    window.localStorage[
        _sessionKey(session.courseId, session.lessonId, session.fingerprint)] =
      session.toStoragePayload();
  } catch (_) {
    // Ignore localStorage write failures.
  }
}

void _clearSession(WavResumableSession session) {
  _clearSessionByKey(session.courseId, session.lessonId, session.fingerprint);
}

void _clearSessionByKey(String courseId, String lessonId, String fingerprint) {
  try {
    window.localStorage.remove(_sessionKey(courseId, lessonId, fingerprint));
  } catch (_) {
    // Ignore localStorage errors.
  }
}

Future<ByteBuffer> _readBlobAsBuffer(Blob blob) {
  final reader = FileReader();
  final completer = Completer<ByteBuffer>();

  reader.onError.listen((_) {
    if (completer.isCompleted) return;
    completer.completeError(const WavUploadFailure(WavUploadFailureKind.failed));
  });

  reader.onLoadEnd.listen((_) {
    if (completer.isCompleted) return;
    final result = reader.result;
    if (result is ByteBuffer) {
      completer.complete(result);
    } else if (result is Uint8List) {
      completer.complete(result.buffer);
    } else {
      completer.completeError(
        const WavUploadFailure(WavUploadFailureKind.failed),
      );
    }
  });

  reader.readAsArrayBuffer(blob);
  return completer.future;
}

String _bytesToHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

Future<String> _hashBlob(Blob blob) async {
  final buffer = await _readBlobAsBuffer(blob);
  final digest = sha256.convert(Uint8List.view(buffer)).bytes;
  return _bytesToHex(Uint8List.fromList(digest));
}

_SignedUploadInfo _parseSignedUploadInfo(Uri uploadUrl) {
  final token = uploadUrl.queryParameters['token'] ??
      uploadUrl.queryParameters['signature'];
  if (token == null || token.isEmpty) {
    throw const WavUploadFailure(WavUploadFailureKind.failed);
  }

  final segments = uploadUrl.pathSegments;
  final signIndex = segments.indexOf('sign');
  if (signIndex == -1 || signIndex + 1 >= segments.length) {
    throw const WavUploadFailure(WavUploadFailureKind.failed);
  }
  final bucket = segments[signIndex + 1];
  final storageBaseUrl = Uri.parse(
    '${uploadUrl.origin}/storage/v1',
  );

  return _SignedUploadInfo(
    storageBaseUrl: storageBaseUrl,
    bucket: bucket,
    token: token,
  );
}

String _normalizeObjectPath(String bucket, String objectPath) {
  if (objectPath.startsWith('$bucket/')) {
    return objectPath.substring(bucket.length + 1);
  }
  return objectPath;
}

Map<String, String> _baseTusHeaders(WavResumableSession session) {
  final headers = <String, String>{
    'Tus-Resumable': _tusVersion,
    'x-signature': session.token,
  };
  headers.addAll(session.resumableHeaders());
  return headers;
}

String? _headerValue(Map<String, String> headers, String key) {
  final lowerKey = key.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lowerKey) {
      return entry.value;
    }
  }
  return null;
}

String _buildMetadataHeader(Map<String, String> metadata) {
  final entries = <String>[];
  for (final entry in metadata.entries) {
    final value = entry.value.trim();
    if (value.isEmpty) continue;
    final encoded = base64.encode(utf8.encode(value));
    entries.add('${entry.key} $encoded');
  }
  return entries.join(',');
}

Future<WavResumableSession> _createResumableSession({
  required String mediaId,
  required String courseId,
  required String lessonId,
  required Uri uploadUrl,
  required String objectPath,
  required Map<String, String> headers,
  required WavUploadFile file,
  required String contentType,
}) async {
  final signedInfo = _parseSignedUploadInfo(uploadUrl);
  final cacheControl = _headerValue(headers, 'cache-control');
  final upsertHeader = _headerValue(headers, 'x-upsert') ?? 'false';
  final upsert = upsertHeader.toLowerCase() == 'true';
  final normalizedPath = _normalizeObjectPath(signedInfo.bucket, objectPath);
  final fingerprint = await file.contentFingerprint();

  final metadataHeader = _buildMetadataHeader({
    'bucketName': signedInfo.bucket,
    'objectName': normalizedPath,
    'contentType': contentType,
    if (cacheControl != null) 'cacheControl': cacheControl,
  });

  final endpoint = signedInfo.storageBaseUrl.replace(
    path: '${signedInfo.storageBaseUrl.path}/upload/resumable',
  );

  final response = await _sendTusRequest(
    'POST',
    endpoint,
    headers: {
      'Tus-Resumable': _tusVersion,
      'Upload-Length': file.size.toString(),
      'Upload-Metadata': metadataHeader,
      'x-upsert': upsert ? 'true' : 'false',
      'x-signature': signedInfo.token,
    },
  );

  if (response.status < 200 || response.status >= 300) {
    throw WavUploadFailure(
      WavUploadFailureKind.failed,
      detail: 'create:${response.status}',
    );
  }

  final location = response.headers['location'];
  if (location == null || location.isEmpty) {
    throw const WavUploadFailure(WavUploadFailureKind.failed);
  }
  final sessionUrl = _resolveLocation(endpoint, location);
  final expiresAt = _parseUploadExpires(response.headers['upload-expires']);

  final session = WavResumableSession(
    mediaId: mediaId,
    courseId: courseId,
    lessonId: lessonId,
    sessionUrl: sessionUrl,
    token: signedInfo.token,
    bucket: signedInfo.bucket,
    objectPath: normalizedPath,
    contentType: contentType,
    size: file.size,
    fileName: file.name,
    fingerprint: fingerprint,
    upsert: upsert,
    cacheControl: cacheControl,
    lastModified: null,
    offset: 0,
    expiresAt: expiresAt,
    createdAt: DateTime.now().toUtc(),
  );

  _storeSession(session);
  return session;
}

DateTime? _parseUploadExpires(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

Uri _resolveLocation(Uri base, String location) {
  final uri = Uri.parse(location);
  if (uri.hasScheme) return uri;
  return base.resolve(location);
}

bool _isSigningFailureResponse(_TusResponse response) {
  if (response.status != 400) return false;
  final body = response.body.trim();
  if (body.isEmpty) return false;
  final lower = body.toLowerCase();
  if (lower.contains('signing') || lower.contains('signature')) return true;
  if (lower.contains('signed url') || lower.contains('signedurl')) return true;
  if (lower.contains('token') && lower.contains('expired')) return true;
  if (lower.contains('jwt') && lower.contains('expired')) return true;
  return false;
}

Future<int> _fetchOffset(
  Uri sessionUrl,
  Map<String, String> headers, {
  WavUploadCancelToken? cancelToken,
}) async {
  final response = await _sendTusRequest(
    'HEAD',
    sessionUrl,
    headers: headers,
    cancelToken: cancelToken,
  );

  if (response.status == 404 || response.status == 410) {
    throw const WavUploadFailure(WavUploadFailureKind.expired);
  }
  if (response.status == 401 || response.status == 403) {
    throw const WavUploadFailure(WavUploadFailureKind.expired);
  }
  if (_isSigningFailureResponse(response)) {
    throw const WavUploadFailure(WavUploadFailureKind.expired);
  }
  if (response.status < 200 || response.status >= 300) {
    throw WavUploadFailure(
      WavUploadFailureKind.failed,
      detail: 'head:${response.status}',
    );
  }

  final offsetRaw = response.headers['upload-offset'];
  if (offsetRaw == null || offsetRaw.isEmpty) {
    throw const WavUploadFailure(WavUploadFailureKind.failed);
  }
  return int.tryParse(offsetRaw) ?? 0;
}

Future<int> _uploadChunkWithRetry(
  Uri sessionUrl,
  Blob chunk,
  int offset,
  Map<String, String> baseHeaders, {
  WavUploadCancelToken? cancelToken,
}) async {
  final retryDelays = <Duration>[
    Duration.zero,
    const Duration(seconds: 3),
    const Duration(seconds: 5),
    const Duration(seconds: 10),
    const Duration(seconds: 20),
  ];

  WavUploadFailure? lastFailure;

  for (var attempt = 0; attempt < retryDelays.length; attempt += 1) {
    if (cancelToken?.isCancelled == true) {
      throw const WavUploadFailure(WavUploadFailureKind.cancelled);
    }

    final delay = retryDelays[attempt];
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }

    try {
      final response = await _sendTusRequest(
        'PATCH',
        sessionUrl,
        headers: {
          ...baseHeaders,
          'Upload-Offset': offset.toString(),
          'Content-Type': 'application/offset+octet-stream',
        },
        body: chunk,
        cancelToken: cancelToken,
      );

      if (response.status == 409) {
        final serverOffset = await _fetchOffset(
          sessionUrl,
          baseHeaders,
          cancelToken: cancelToken,
        );
        return serverOffset;
      }
      if (response.status == 404 || response.status == 410) {
        throw const WavUploadFailure(WavUploadFailureKind.expired);
      }
      if (response.status == 401 || response.status == 403) {
        throw const WavUploadFailure(WavUploadFailureKind.expired);
      }
      if (_isSigningFailureResponse(response)) {
        throw const WavUploadFailure(WavUploadFailureKind.expired);
      }
      if (response.status < 200 || response.status >= 300) {
        throw WavUploadFailure(
          WavUploadFailureKind.failed,
          detail: 'patch:${response.status}',
        );
      }

      final offsetRaw = response.headers['upload-offset'];
      if (offsetRaw == null || offsetRaw.isEmpty) {
        throw const WavUploadFailure(WavUploadFailureKind.failed);
      }
      return int.tryParse(offsetRaw) ?? offset;
    } on WavUploadFailure catch (error) {
      if (error.kind == WavUploadFailureKind.cancelled) {
        throw error;
      }
      if (error.kind == WavUploadFailureKind.expired) {
        throw error;
      }
      lastFailure = error;
    }
  }

  throw lastFailure ?? const WavUploadFailure(WavUploadFailureKind.failed);
}

class _TusResponse {
  const _TusResponse({
    required this.status,
    required this.headers,
    required this.body,
  });

  final int status;
  final Map<String, String> headers;
  final String body;
}

Future<_TusResponse> _sendTusRequest(
  String method,
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  WavUploadCancelToken? cancelToken,
}) async {
  final request = HttpRequest();
  final completer = Completer<_TusResponse>();

  request.open(method, url.toString());
  request.responseType = 'text';

  headers?.forEach((key, value) {
    request.setRequestHeader(key, value);
  });

  if (cancelToken != null) {
    cancelToken.onCancel(request.abort);
  }

  request.onAbort.listen((_) {
    if (completer.isCompleted) return;
    completer.completeError(
      const WavUploadFailure(WavUploadFailureKind.cancelled),
    );
  });

  request.onError.listen((_) {
    if (completer.isCompleted) return;
    completer.completeError(
      const WavUploadFailure(WavUploadFailureKind.failed),
    );
  });

  request.onLoadEnd.listen((_) {
    if (completer.isCompleted) return;
    final status = request.status ?? 0;
    if (status == 0) {
      completer.completeError(
        const WavUploadFailure(WavUploadFailureKind.failed),
      );
      return;
    }
    completer.complete(
      _TusResponse(
        status: status,
        headers: _parseHeaders(request.getAllResponseHeaders()),
        body: request.responseText ?? '',
      ),
    );
  });

  request.send(body);
  return completer.future;
}

Map<String, String> _parseHeaders(String raw) {
  final headers = <String, String>{};
  if (raw.isEmpty) return headers;
  final lines = raw.split('\n');
  for (final line in lines) {
    final index = line.indexOf(':');
    if (index <= 0) continue;
    final key = line.substring(0, index).trim().toLowerCase();
    final value = line.substring(index + 1).trim();
    if (key.isEmpty) continue;
    headers[key] = value;
  }
  return headers;
}
