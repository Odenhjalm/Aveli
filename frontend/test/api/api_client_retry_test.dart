import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/core/auth/token_storage.dart';

void main() {
  test('ApiClient does not retry multipart FormData on 401', () async {
    final storage = _MemoryFlutterSecureStorage();
    final tokens = TokenStorage(storage: storage);
    await tokens.saveTokens(accessToken: 'at-1', refreshToken: 'rt-1');

    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:1',
      tokenStorage: tokens,
    );

    final adapter = _RecordingAdapter(
      (options) {
        if (options.path == '/studio/home-player/uploads') {
          return _jsonResponse(
            statusCode: 401,
            body: {'detail': 'unauthorized'},
          );
        }
        if (options.path == ApiPaths.authRefresh) {
          return _jsonResponse(
            statusCode: 200,
            body: {'access_token': 'at-2', 'refresh_token': 'rt-2'},
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      },
    );
    client.raw.httpClientAdapter = adapter;

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        filename: 'test.bin',
      ),
    });

    DioException? thrown;
    try {
      await client.postForm<Map<String, dynamic>>(
        '/studio/home-player/uploads',
        formData,
      );
    } catch (err) {
      thrown = err as DioException;
    }

    expect(thrown?.response?.statusCode, 401);
    expect(adapter.count('/studio/home-player/uploads'), 1);
    expect(adapter.count(ApiPaths.authRefresh), 0);
  });

  test('ApiClient retries JSON requests on 401 after refreshing token', () async {
    final storage = _MemoryFlutterSecureStorage();
    final tokens = TokenStorage(storage: storage);
    await tokens.saveTokens(accessToken: 'at-1', refreshToken: 'rt-1');

    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:1',
      tokenStorage: tokens,
    );

    final adapter = _RecordingAdapter(
      (options) {
        if (options.path == ApiPaths.authRefresh) {
          return _jsonResponse(
            statusCode: 200,
            body: {'access_token': 'at-2', 'refresh_token': 'rt-2'},
          );
        }

        if (options.path == '/api/some') {
          final auth = options.headers['Authorization']?.toString();
          if (auth == 'Bearer at-1') {
            return _jsonResponse(
              statusCode: 401,
              body: {'detail': 'unauthorized'},
            );
          }
          return _jsonResponse(statusCode: 200, body: {'value': 1});
        }

        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      },
    );
    client.raw.httpClientAdapter = adapter;

    final res = await client.get<Map<String, dynamic>>('/api/some');

    expect(res['value'], 1);
    expect(adapter.count('/api/some'), 2);
    expect(adapter.count(ApiPaths.authRefresh), 1);
  });
}

ResponseBody _jsonResponse({
  required int statusCode,
  required Map<String, dynamic> body,
}) {
  return ResponseBody.fromString(
    json.encode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._handler);

  final ResponseBody Function(RequestOptions options) _handler;
  final List<_RecordedRequest> _requests = <_RecordedRequest>[];

  int count(String path) =>
      _requests.where((request) => request.path == path).length;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _requests.add(
      _RecordedRequest(
        path: options.path,
        method: options.method,
        headers: Map<String, dynamic>.from(options.headers),
      ),
    );
    return _handler(options);
  }
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.path,
    required this.method,
    required this.headers,
  });

  final String path;
  final String method;
  final Map<String, dynamic> headers;
}

class _MemoryFlutterSecureStorage extends FlutterSecureStorage {
  _MemoryFlutterSecureStorage();

  final Map<String, String?> _storage = <String, String?>{};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _storage[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _storage[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _storage.remove(key);
  }
}

