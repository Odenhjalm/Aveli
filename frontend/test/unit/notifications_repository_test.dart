import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/features/community/data/notifications_repository.dart';

void main() {
  test('myNotifications reads backend notification read model', () async {
    final harness = await _Harness.create();
    final repository = NotificationsRepository(harness.client);

    final readModel = await repository.myNotifications();

    expect(readModel.showNotificationsBar, isTrue);
    expect(readModel.notifications, hasLength(1));
    expect(readModel.notifications.single.id, 'notification-1');
    expect(readModel.notifications.single.title, 'Ny lektion ar upplast');
    expect(readModel.notifications.single.subtitle, 'Lesson one');
    expect(readModel.notifications.single.ctaLabel, 'Oppna lektionen');
    expect(readModel.notifications.single.ctaUrl, '/lesson/lesson-1');
    final requests = harness.adapter.requestsFor('/notifications');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
  });

  test(
    'myNotifications reads hidden notification bar without placeholders',
    () async {
      final harness = await _Harness.create(emptyNotifications: true);
      final repository = NotificationsRepository(harness.client);

      final readModel = await repository.myNotifications();

      expect(readModel.showNotificationsBar, isFalse);
      expect(readModel.notifications, isEmpty);
    },
  );

  test(
    'markRead sends read intent to backend and parses header item',
    () async {
      final harness = await _Harness.create();
      final repository = NotificationsRepository(harness.client);

      final notification = await repository.markRead('notification-1');

      expect(notification.id, 'notification-1');
      expect(notification.title, 'Ny lektion ar upplast');
      expect(notification.subtitle, 'Lesson one');
      expect(notification.ctaLabel, 'Oppna lektionen');
      expect(notification.ctaUrl, '/lesson/lesson-1');
      final requests = harness.adapter.requestsFor(
        '/notifications/notification-1/read',
      );
      expect(requests, hasLength(1));
      expect(requests.single.method, 'PATCH');
    },
  );

  test('registerDevice sends token and platform to backend', () async {
    final harness = await _Harness.create();
    final repository = NotificationsRepository(harness.client);

    final device = await repository.registerDevice(
      pushToken: 'push-token-1',
      platform: 'android',
    );

    expect(device.id, 'device-1');
    expect(device.active, isTrue);
    final requests = harness.adapter.requestsFor('/notifications/devices');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.data, {
      'push_token': 'push-token-1',
      'platform': 'android',
    });
  });

  test('deactivateDevice uses device scoped route', () async {
    final harness = await _Harness.create();
    final repository = NotificationsRepository(harness.client);

    await repository.deactivateDevice('device-1');

    final requests = harness.adapter.requestsFor(
      '/notifications/devices/device-1',
    );
    expect(requests, hasLength(1));
    expect(requests.single.method, 'DELETE');
  });
}

class _Harness {
  _Harness({required this.client, required this.adapter});

  final ApiClient client;
  final _RecordingAdapter adapter;

  static Future<_Harness> create({bool emptyNotifications = false}) async {
    final storage = _MemoryFlutterSecureStorage();
    final tokens = TokenStorage(storage: storage);
    await tokens.saveTokens(
      accessToken: _jwtWithExpSeconds(4102444800),
      refreshToken: 'rt-1',
    );

    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:1',
      tokenStorage: tokens,
    );
    final adapter = _RecordingAdapter(
      (options) =>
          _defaultHandler(options, emptyNotifications: emptyNotifications),
    );
    client.raw.httpClientAdapter = adapter;
    return _Harness(client: client, adapter: adapter);
  }
}

ResponseBody _defaultHandler(
  RequestOptions options, {
  required bool emptyNotifications,
}) {
  final method = options.method.toUpperCase();
  if (options.path == '/notifications' && method == 'GET') {
    if (emptyNotifications) {
      return _jsonResponse(
        statusCode: 200,
        body: {'show_notifications_bar': false, 'notifications': const []},
      );
    }
    return _jsonResponse(
      statusCode: 200,
      body: {
        'show_notifications_bar': true,
        'notifications': [
          {
            'id': 'notification-1',
            'title': 'Ny lektion ar upplast',
            'subtitle': 'Lesson one',
            'cta_label': 'Oppna lektionen',
            'cta_url': '/lesson/lesson-1',
          },
        ],
      },
    );
  }
  if (options.path == '/notifications/notification-1/read' &&
      method == 'PATCH') {
    return _jsonResponse(
      statusCode: 200,
      body: {
        'id': 'notification-1',
        'title': 'Ny lektion ar upplast',
        'subtitle': 'Lesson one',
        'cta_label': 'Oppna lektionen',
        'cta_url': '/lesson/lesson-1',
      },
    );
  }
  if (options.path == '/notifications/devices' && method == 'POST') {
    return _jsonResponse(
      statusCode: 200,
      body: {
        'id': 'device-1',
        'user_id': 'user-1',
        'push_token': (options.data as Map)['push_token'],
        'platform': (options.data as Map)['platform'],
        'active': true,
        'created_at': '2026-04-25T09:00:00Z',
      },
    );
  }
  if (options.path == '/notifications/devices/device-1' && method == 'DELETE') {
    return _jsonResponse(statusCode: 204, body: const {});
  }
  return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
}

ResponseBody _jsonResponse({
  required int statusCode,
  required Map<String, Object?> body,
}) {
  return ResponseBody.fromString(
    json.encode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

String _jwtWithExpSeconds(int expSeconds) {
  final header = base64Url.encode(utf8.encode(json.encode({'alg': 'HS256'})));
  final payload = base64Url.encode(
    utf8.encode(json.encode({'exp': expSeconds})),
  );
  return '$header.$payload.signature';
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._handler);

  final ResponseBody Function(RequestOptions options) _handler;
  final List<_RecordedRequest> _requests = <_RecordedRequest>[];

  List<_RecordedRequest> requestsFor(String path) => _requests
      .where((request) => request.path == path)
      .toList(growable: false);

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
        method: options.method.toUpperCase(),
        data: options.data,
      ),
    );
    return _handler(options);
  }
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.path,
    required this.method,
    required this.data,
  });

  final String path;
  final String method;
  final Object? data;
}

class _MemoryFlutterSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    _values.clear();
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    return Map<String, String>.from(_values);
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    return _values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }
}
