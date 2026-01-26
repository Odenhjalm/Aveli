import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/presentation/teacher_home_page.dart';
import 'package:aveli/features/teacher/application/bundle_providers.dart';

class _FakeTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> updateAccessToken(String accessToken) async {}
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future? cancelFuture,
  ) {
    return _handler(options);
  }
}

void main() {
  testWidgets('teacher can delete a course from teacher home', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final tokenStorage = _FakeTokenStorage();
    final client = ApiClient(baseUrl: 'http://localhost', tokenStorage: tokenStorage);
    String? deletedPath;

    client.raw.httpClientAdapter = _StubAdapter((options) async {
      if (options.method.toUpperCase() == 'DELETE') {
        deletedPath = options.path;
        return ResponseBody.fromString(
          jsonEncode({'deleted': true}),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      }
      return ResponseBody.fromString(
        jsonEncode({}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    });

    final studioRepo = StudioRepository(client: client);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost',
              stripePublishableKey: '',
              stripeMerchantDisplayName: 'Test',
              subscriptionsEnabled: false,
            ),
          ),
          tokenStorageProvider.overrideWithValue(tokenStorage),
          studioRepositoryProvider.overrideWithValue(studioRepo),
          myCoursesProvider.overrideWith(
            (ref) async => [
              {
                'id': 'course-1',
                'title': 'Min kurs',
                'branch': 'Allmänt',
                'is_free_intro': true,
                'is_published': false,
              },
            ],
          ),
          teacherBundlesProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: TeacherHomeScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Min kurs'), findsOneWidget);

    await tester.tap(find.byTooltip('Ta bort kurs'));
    await tester.pumpAndSettle();

    expect(find.text('Ta bort kurs'), findsOneWidget);

    await tester.tap(find.text('Ta bort'));
    await tester.pumpAndSettle();

    expect(find.text('Min kurs'), findsNothing);
    expect(deletedPath, '/studio/courses/course-1');
  });
}
