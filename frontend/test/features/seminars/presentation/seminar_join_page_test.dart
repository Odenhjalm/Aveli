import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/core/auth/token_storage.dart';
import 'package:wisdom/core/env/app_config.dart';
import 'package:wisdom/data/models/seminar.dart';
import 'package:wisdom/data/repositories/seminar_repository.dart';
import 'package:wisdom/features/home/application/livekit_controller.dart';
import 'package:wisdom/features/seminars/application/seminar_providers.dart';
import 'package:wisdom/features/seminars/presentation/seminar_join_page.dart';
import 'package:wisdom/shared/utils/backend_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SeminarJoinPage', () {
    testWidgets(
      'renders without cache asserts when initial constraints are zero',
      (tester) async {
        const seminarId = 'test-seminar';
        final now = DateTime(2024, 1, 1);
        final detail = SeminarDetail(
          seminar: Seminar(
            id: seminarId,
            hostId: 'host',
            title: 'Testseminarium',
            description: 'Beskrivning',
            status: SeminarStatus.live,
            scheduledAt: now,
            durationMinutes: 45,
            livekitRoom: 'room',
            livekitMetadata: const {},
            createdAt: now,
            updatedAt: now,
          ),
          sessions: [
            SeminarSession(
              id: 'session-1',
              seminarId: seminarId,
              status: SeminarSessionStatus.live,
              scheduledAt: now,
              startedAt: now,
              endedAt: null,
              livekitRoom: 'room',
              livekitSid: 'sid-1',
              metadata: const {},
              createdAt: now,
              updatedAt: now,
            ),
          ],
          attendees: const [],
          recordings: const [],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appConfigProvider.overrideWithValue(
                const AppConfig(
                  apiBaseUrl: '',
                  stripePublishableKey: '',
                  stripeMerchantDisplayName: '',
                  subscriptionsEnabled: false,
                ),
              ),
              publicSeminarDetailProvider(
                seminarId,
              ).overrideWith((ref) async => detail),
              liveSessionControllerProvider.overrideWith(
                _DummyLiveSessionController.new,
              ),
              seminarRepositoryProvider.overrideWithValue(
                _NoopSeminarRepository(),
              ),
              backendAssetResolverProvider.overrideWithValue(
                _FakeBackendAssetResolver(),
              ),
            ],
            child: const MediaQuery(
              data: MediaQueryData(size: Size.zero, devicePixelRatio: 0),
              child: MaterialApp(home: SeminarJoinPage(seminarId: seminarId)),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('Delta i liveseminarium'), findsOneWidget);
      },
    );
  });
}

class _DummyLiveSessionController extends LiveSessionController {
  @override
  LiveSessionState build() => const LiveSessionState();

  @override
  Future<void> connect(
    String seminarId, {
    bool micEnabled = true,
    bool cameraEnabled = true,
  }) async {}

  @override
  Future<void> connectWithToken({
    required String wsUrl,
    required String token,
    bool micEnabled = true,
    bool cameraEnabled = true,
  }) async {}

  @override
  Future<void> disconnect() async {
    state = const LiveSessionState();
  }

  @override
  Future<void> setScreenShareEnabled(bool enable) async {}
}

class _NoopSeminarRepository extends SeminarRepository {
  _NoopSeminarRepository()
    : super(
        ApiClient(
          baseUrl: 'http://127.0.0.1:8080',
          tokenStorage: const TokenStorage(
            storage: _FakeFlutterSecureStorage(),
          ),
        ),
      );

  @override
  Future<SeminarRegistration> registerForSeminar(String id) async {
    final now = DateTime(2024, 1, 1);
    return SeminarRegistration(
      seminarId: id,
      userId: 'user',
      role: 'participant',
      inviteStatus: 'accepted',
      joinedAt: now,
      leftAt: null,
      livekitIdentity: null,
      livekitParticipantSid: null,
      createdAt: now,
    );
  }

  @override
  Future<void> unregisterFromSeminar(String id) async {}
}

class _FakeFlutterSecureStorage extends FlutterSecureStorage {
  const _FakeFlutterSecureStorage();

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
  }) async {}

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => null;

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => const {};

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => false;
}

class _FakeBackendAssetResolver extends BackendAssetResolver {
  _FakeBackendAssetResolver() : super('');

  static final Uint8List _transparentImageBytes = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, //
    0x49, 0x48, 0x44, 0x52, //
    0x00, 0x00, 0x00, 0x01, //
    0x00, 0x00, 0x00, 0x01, //
    0x08, 0x06, 0x00, 0x00, 0x00, //
    0x1F, 0x15, 0xC4, 0x89, //
    0x00, 0x00, 0x00, 0x0A, //
    0x49, 0x44, 0x41, 0x54, //
    0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, //
    0x0D, 0x0A, 0x2D, 0xB4, //
    0x00, 0x00, 0x00, 0x00, //
    0x49, 0x45, 0x4E, 0x44, //
    0xAE, 0x42, 0x60, 0x82,
  ]);

  @override
  ImageProvider<Object> imageProvider(String assetPath, {double scale = 1.0}) {
    return MemoryImage(_transparentImageBytes, scale: scale);
  }
}
