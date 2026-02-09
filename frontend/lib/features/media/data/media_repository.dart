import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/core/env/app_config.dart';

import 'media_resolution_mode.dart';

class MediaSignedUrl {
  const MediaSignedUrl({
    required this.mediaId,
    required this.signedUrl,
    required this.expiresAt,
  });

  final String mediaId;
  final String signedUrl;
  final DateTime expiresAt;

  factory MediaSignedUrl.fromJson(Map<String, dynamic> json) {
    final mediaId = json['media_id']?.toString() ?? '';
    final signedUrl = json['signed_url']?.toString() ?? '';
    final expiresRaw = json['expires_at']?.toString() ?? '';
    final expiresAt = DateTime.tryParse(expiresRaw) ?? DateTime.now().toUtc();
    return MediaSignedUrl(
      mediaId: mediaId,
      signedUrl: signedUrl,
      expiresAt: expiresAt.toUtc(),
    );
  }

  bool isValid({Duration leeway = const Duration(seconds: 30)}) {
    return signedUrl.isNotEmpty &&
        DateTime.now().toUtc().isBefore(expiresAt.subtract(leeway));
  }
}

class MediaRepository {
  MediaRepository({required ApiClient client, required AppConfig config})
    : _client = client,
      _config = config;

  final ApiClient _client;
  final AppConfig _config;

  Directory? _cacheDir;
  final Map<String, Future<File>> _inflight = {};
  final Map<String, Uint8List> _memoryCache = {};
  final Map<String, MediaSignedUrl> _signedUrlCache = {};
  final Map<String, Future<MediaSignedUrl>> _signedUrlInflight = {};

  Future<MediaSignedUrl> signMedia(
    String mediaId, {
    MediaResolutionMode mode = MediaResolutionMode.studentRender,
    Duration leeway = const Duration(seconds: 30),
  }) {
    final normalized = mediaId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('mediaId may not be empty');
    }

    final cacheKey = '$normalized::${mode.apiValue}';
    final cached = _signedUrlCache[cacheKey];
    if (cached != null && cached.isValid(leeway: leeway)) {
      return Future.value(cached);
    }

    final pending = _signedUrlInflight[cacheKey];
    if (pending != null) return pending;

    final future = _signMedia(normalized, mode: mode);
    _signedUrlInflight[cacheKey] = future;
    future.whenComplete(() => _signedUrlInflight.remove(cacheKey));
    return future;
  }

  Future<MediaSignedUrl> _signMedia(
    String mediaId, {
    required MediaResolutionMode mode,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiPaths.mediaSign,
      body: {'media_id': mediaId, 'mode': mode.apiValue},
    );
    final signed = MediaSignedUrl.fromJson(response);
    final cacheKey = '$mediaId::${mode.apiValue}';
    _signedUrlCache[cacheKey] = signed;
    return signed;
  }

  Future<Directory> _ensureCacheDir() async {
    final existing = _cacheDir;
    if (existing != null) return existing;

    if (kIsWeb) {
      throw UnsupportedError(
        'File cache is not available on the web platform.',
      );
    }

    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/aveli_media');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Resolve a relative download path to an absolute URL based on the API base.
  String resolveUrl(String downloadPath) {
    final target = _normalizeDownloadTarget(downloadPath);
    if (target.isAbsolute) return target.path;
    final base = Uri.parse(_config.apiBaseUrl);
    return base.resolve(target.path).toString();
  }

  /// Download a media asset (if needed) and return the cached file on disk.
  Future<File> cacheMedia({
    required String cacheKey,
    required String downloadPath,
    String? fileExtension,
  }) {
    if (kIsWeb) {
      throw UnsupportedError(
        'File cache is not available on the web platform.',
      );
    }

    final target = _normalizeDownloadTarget(downloadPath);
    final key = '$cacheKey::${target.path}';
    final pending = _inflight[key];
    if (pending != null) return pending;

    final future = _cacheMedia(
      cacheKey: key,
      requestPath: target.path,
      skipAuth: target.skipAuth,
      fileExtension: fileExtension,
    );
    _inflight[key] = future;
    future.whenComplete(() => _inflight.remove(key));
    return future;
  }

  Future<File> _cacheMedia({
    required String cacheKey,
    required String requestPath,
    required bool skipAuth,
    String? fileExtension,
  }) async {
    final dir = await _ensureCacheDir();
    final hash = sha1.convert(utf8.encode(cacheKey)).toString();
    final ext = _sanitizeExtension(fileExtension);
    final fileName = ext == null ? hash : '$hash.$ext';
    final file = File('${dir.path}/$fileName');

    if (await file.exists()) {
      return file;
    }

    final bytes = await _client.getBytes(requestPath, skipAuth: skipAuth);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<Uint8List> cacheMediaBytes({
    required String cacheKey,
    required String downloadPath,
    String? fileExtension,
  }) async {
    if (kIsWeb) {
      final target = _normalizeDownloadTarget(downloadPath);
      final key = '$cacheKey::${target.path}';
      final existing = _memoryCache[key];
      if (existing != null) return existing;
      final bytes = await _client.getBytes(
        target.path,
        skipAuth: target.skipAuth,
      );
      _memoryCache[key] = bytes;
      return bytes;
    }

    final file = await cacheMedia(
      cacheKey: cacheKey,
      downloadPath: downloadPath,
      fileExtension: fileExtension,
    );
    return file.readAsBytes();
  }

  /// Delete cached files older than [maxAge].
  Future<void> purgeOlderThan(Duration maxAge) async {
    if (kIsWeb) {
      _memoryCache.clear();
      return;
    }

    final dir = await _ensureCacheDir();
    final threshold = DateTime.now().subtract(maxAge);
    final entries = dir.list();
    await for (final entity in entries) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      if (stat.modified.isBefore(threshold)) {
        try {
          await entity.delete();
        } catch (_) {
          // Ignore IO errors when purging old cache files.
        }
      }
    }
  }

  /// Remove all cached media files.
  Future<void> clearCache() async {
    if (kIsWeb) {
      _memoryCache.clear();
      return;
    }

    final dir = await _ensureCacheDir();
    if (!await dir.exists()) return;
    final entries = dir.list();
    await for (final entity in entries) {
      if (entity is File) {
        try {
          await entity.delete();
        } catch (_) {
          // Ignore IO errors when clearing cache.
        }
      }
    }
  }

  _DownloadTarget _normalizeDownloadTarget(String input) {
    if (input.isEmpty) {
      throw ArgumentError('downloadPath may not be empty');
    }

    if (input.startsWith('http://') || input.startsWith('https://')) {
      final uri = Uri.parse(input);
      final base = Uri.parse(_config.apiBaseUrl);
      final sameOrigin =
          uri.scheme == base.scheme &&
          uri.host == base.host &&
          uri.port == base.port;
      if (!sameOrigin) {
        if (_isAllowedSupabaseUri(uri)) {
          return _DownloadTarget(
            path: uri.toString(),
            skipAuth: true,
            isAbsolute: true,
          );
        }
        throw ArgumentError('downloadPath must target the configured API host.');
      }
      final path = uri.path.isEmpty ? '/' : uri.path;
      final query = uri.hasQuery ? '?${uri.query}' : '';
      return _DownloadTarget(path: '$path$query', skipAuth: false);
    }

    return _DownloadTarget(
      path: input.startsWith('/') ? input : '/$input',
      skipAuth: false,
    );
  }

  bool _isAllowedSupabaseUri(Uri uri) {
    final rawBase = _config.supabaseUrl.trim();
    if (rawBase.isEmpty) return false;
    final base = Uri.tryParse(rawBase);
    if (base == null || base.host.isEmpty) return false;

    final sameOrigin =
        uri.scheme == base.scheme &&
        uri.host == base.host &&
        uri.port == base.port;
    if (!sameOrigin) return false;

    final normalizedPath = uri.path.trim();
    if (!normalizedPath.startsWith('/storage/v1/')) return false;
    return true;
  }

  String? _sanitizeExtension(String? input) {
    if (input == null || input.isEmpty) return null;
    final sanitized = input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return sanitized.isEmpty ? null : sanitized;
  }
}

class _DownloadTarget {
  const _DownloadTarget({
    required this.path,
    required this.skipAuth,
    this.isAbsolute = false,
  });

  final String path;
  final bool skipAuth;
  final bool isAbsolute;
}
