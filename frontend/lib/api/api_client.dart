import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:wisdom/core/auth/auth_http_observer.dart';
import 'package:wisdom/core/auth/token_storage.dart';

class ApiClient {
  ApiClient({
    required String baseUrl,
    required TokenStorage tokenStorage,
    AuthHttpObserver? authObserver,
  }) : _tokenStorage = tokenStorage,
       _authObserver = authObserver,
       _dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 15),
           contentType: 'application/json',
         ),
       ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.extra['skipAuth'] == true) {
            handler.next(options);
            return;
          }
          final token = await _tokenStorage.readAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final response = error.response;
          final requestOptions = error.requestOptions;
          final alreadyRetried = requestOptions.extra['retried'] == true;
          final skipAuth = requestOptions.extra['skipAuth'] == true;
          var sessionExpiredHandled = false;

          if (response?.statusCode == 403 && !skipAuth) {
            _notifyForbidden();
            handler.next(error);
            return;
          }

          if (response?.statusCode == 401 && !alreadyRetried && !skipAuth) {
            final refreshed = await _refreshAccessToken();
            if (refreshed) {
              final newToken = await _tokenStorage.readAccessToken();
              if (newToken != null && newToken.isNotEmpty) {
                requestOptions.headers['Authorization'] = 'Bearer $newToken';
              }
              requestOptions.extra['retried'] = true;
              try {
                final retryResponse = await _dio.fetch(requestOptions);
                handler.resolve(retryResponse);
                return;
              } catch (retryError) {
                final dioError = retryError is DioException
                    ? retryError
                    : error;
                handler.next(dioError);
                return;
              }
            } else {
              final clearedAlready =
                  requestOptions.extra['sessionExpiredCleared'] == true;
              if (!clearedAlready) {
                await _tokenStorage.clear();
                requestOptions.extra['sessionExpiredCleared'] = true;
              }
              sessionExpiredHandled = true;
            }
          }
          if (response?.statusCode == 401) {
            if (!sessionExpiredHandled) {
              final clearedAlready =
                  requestOptions.extra['sessionExpiredCleared'] == true;
              if (!clearedAlready) {
                await _tokenStorage.clear();
                requestOptions.extra['sessionExpiredCleared'] = true;
              }
            }
            if (!skipAuth) {
              final alreadyNotified =
                  requestOptions.extra['sessionExpiredNotified'] == true;
              if (!alreadyNotified) {
                requestOptions.extra['sessionExpiredNotified'] = true;
                _notifySessionExpired();
              }
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final AuthHttpObserver? _authObserver;
  Completer<bool>? _refreshCompleter;

  Map<String, dynamic>? _buildExtra(
    Map<String, dynamic>? extra,
    bool skipAuth,
  ) {
    if (!skipAuth && (extra == null || extra.isEmpty)) {
      return extra;
    }
    final merged = <String, dynamic>{if (extra != null) ...extra};
    if (skipAuth) {
      merged['skipAuth'] = true;
    }
    return merged;
  }

  void _notifySessionExpired() {
    _authObserver?.emit(AuthHttpEvent.sessionExpired);
  }

  void _notifyForbidden() {
    _authObserver?.emit(AuthHttpEvent.forbidden);
  }

  Future<bool> _refreshAccessToken() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    final completer = Completer<bool>();
    _refreshCompleter = completer;

    try {
      final refreshToken = await _tokenStorage.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        await _tokenStorage.clear();
        _notifySessionExpired();
        completer.complete(false);
        return false;
      }

      final refreshResponse = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(extra: {'skipAuth': true}),
      );

      final data = refreshResponse.data ?? <String, dynamic>{};
      final newAccess = data['access_token'] as String?;
      final newRefresh = data['refresh_token'] as String?;

      if (newAccess == null || newRefresh == null) {
        await _tokenStorage.clear();
        completer.complete(false);
        return false;
      }

      await _tokenStorage.saveTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
      );
      _dio.options.headers['Authorization'] = 'Bearer $newAccess';
      completer.complete(true);
      return true;
    } catch (_) {
      await _tokenStorage.clear();
      if (!completer.isCompleted) {
        completer.complete(false);
      }
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(Map<String, dynamic> data)? parser,
    bool skipAuth = false,
    Map<String, dynamic>? extra,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      path,
      queryParameters: queryParameters,
      options: Options(extra: _buildExtra(extra, skipAuth)),
    );
    if (parser != null && response.data != null) {
      return parser(response.data!);
    }
    return (response.data as T);
  }

  Future<T> post<T>(
    String path, {
    Map<String, dynamic>? body,
    T Function(Map<String, dynamic> data)? parser,
    bool skipAuth = false,
    Map<String, dynamic>? extra,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      path,
      data: body,
      options: Options(extra: _buildExtra(extra, skipAuth)),
    );
    if (parser != null && response.data != null) {
      return parser(response.data!);
    }
    return (response.data as T);
  }

  Future<T?> patch<T>(
    String path, {
    Map<String, dynamic>? body,
    T Function(Map<String, dynamic> data)? parser,
    bool skipAuth = false,
    Map<String, dynamic>? extra,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      path,
      data: body,
      options: Options(extra: _buildExtra(extra, skipAuth)),
    );
    if (parser != null && response.data != null) {
      return parser(response.data!);
    }
    return response.data as T?;
  }

  Future<T?> postForm<T>(
    String path,
    FormData formData, {
    T Function(Map<String, dynamic> data)? parser,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
    bool skipAuth = false,
    Map<String, dynamic>? extra,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      path,
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        extra: _buildExtra(extra, skipAuth),
      ),
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
    if (parser != null && response.data != null) {
      return parser(response.data!);
    }
    return response.data as T?;
  }

  Future<T?> delete<T>(
    String path, {
    Map<String, dynamic>? body,
    T Function(Map<String, dynamic> data)? parser,
    bool skipAuth = false,
    Map<String, dynamic>? extra,
  }) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      path,
      data: body,
      options: Options(extra: _buildExtra(extra, skipAuth)),
    );
    if (parser != null && response.data != null) {
      return parser(response.data!);
    }
    return response.data as T?;
  }

  Future<Uint8List> getBytes(String path) async {
    final response = await _dio.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data ?? <int>[];
    return Uint8List.fromList(data);
  }

  Dio get raw => _dio;
}
