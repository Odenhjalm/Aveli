import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/env/app_config.dart';

class MediaRepository {
  MediaRepository({required ApiClient client, required AppConfig config})
    : _client = client,
      _config = config;

  final ApiClient _client;
  final AppConfig _config;

  Directory? _cacheDir;
  final Map<String, Future<File>> _inflight = {};
  final Map<String, Uint8List> _memoryCache = {};

  Future<Directory> _ensureCacheDir() async {
    final existing = _cacheDir;
    if (existing != null) return existing;

    if (kIsWeb) {
      throw UnsupportedError(
        'File cache is not available on the web platform.',
      );
    }

    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/wisdom_media');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Resolve a relative download path to an absolute URL based on the API base.
  String resolveUrl(String downloadPath) {
    final normalized = _normalizeDownloadPath(downloadPath);
    final base = Uri.parse(_config.apiBaseUrl);
    return base.resolve(normalized).toString();
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

    final normalizedPath = _normalizeDownloadPath(downloadPath);
    final key = '$cacheKey::$normalizedPath';
    final pending = _inflight[key];
    if (pending != null) return pending;

    final future = _cacheMedia(
      cacheKey: key,
      relativePath: normalizedPath,
      fileExtension: fileExtension,
    );
    _inflight[key] = future;
    future.whenComplete(() => _inflight.remove(key));
    return future;
  }

  Future<File> _cacheMedia({
    required String cacheKey,
    required String relativePath,
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

    final bytes = await _client.getBytes(relativePath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<Uint8List> cacheMediaBytes({
    required String cacheKey,
    required String downloadPath,
    String? fileExtension,
  }) async {
    if (kIsWeb) {
      final normalizedPath = _normalizeDownloadPath(downloadPath);
      final key = '$cacheKey::$normalizedPath';
      final existing = _memoryCache[key];
      if (existing != null) return existing;
      final bytes = await _client.getBytes(normalizedPath);
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

  String _normalizeDownloadPath(String input) {
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
        throw ArgumentError(
          'downloadPath must target the configured API host.',
        );
      }
      final path = uri.path.isEmpty ? '/' : uri.path;
      final query = uri.hasQuery ? '?${uri.query}' : '';
      return '$path$query';
    }

    return input.startsWith('/') ? input : '/$input';
  }

  String? _sanitizeExtension(String? input) {
    if (input == null || input.isEmpty) return null;
    final sanitized = input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return sanitized.isEmpty ? null : sanitized;
  }
}
