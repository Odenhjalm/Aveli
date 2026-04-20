import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/data/repositories/profile_repository.dart';
import 'package:aveli/domain/models/entry_state.dart';
import 'package:aveli/features/community/presentation/profile_page.dart';
import 'package:aveli/features/courses/application/course_providers.dart'
    as courses_front;
import 'package:aveli/features/media/application/profile_avatar_upload_controller.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/media/data/profile_avatar_repository.dart';

const _entryState = EntryState(
  canEnterApp: true,
  onboardingState: 'completed',
  onboardingCompleted: true,
  membershipActive: true,
  needsOnboarding: false,
  needsPayment: false,
  role: 'learner',
);

final _avatarBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
);

Profile _profile({String? avatarMediaId, String? photoUrl}) {
  return Profile(
    id: 'user-1',
    email: 'user@example.com',
    createdAt: DateTime.utc(2024, 1, 1),
    updatedAt: DateTime.utc(2024, 1, 1),
    displayName: 'Aveli User',
    bio: 'Bio',
    avatarMediaId: avatarMediaId,
    photoUrl: photoUrl,
  );
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this.profile);

  Profile profile;
  int updateCalls = 0;

  @override
  Future<Profile?> getMe() async => profile;

  @override
  Future<Profile> updateMe({String? displayName, String? bio}) async {
    updateCalls += 1;
    profile = profile.copyWith(displayName: displayName, bio: bio);
    return profile;
  }
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this.profileRepository)
    : super(_FakeAuthRepository(), AuthHttpObserver()) {
    state = AuthState(
      profile: profileRepository.profile,
      entryState: _entryState,
      hasStoredToken: true,
    );
  }

  final _FakeProfileRepository profileRepository;
  int loadSessionCalls = 0;

  @override
  Future<void> loadSession({bool hydrateProfile = true}) async {
    loadSessionCalls += 1;
    state = state.copyWith(profile: profileRepository.profile);
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<Profile> login({required String email, required String password}) {
    throw UnsupportedError('Not used by this test');
  }

  @override
  Future<Profile> register({required String email, required String password}) {
    throw UnsupportedError('Not used by this test');
  }

  @override
  Future<void> sendVerificationEmail(String email) {
    throw UnsupportedError('Not used by this test');
  }

  @override
  Future<void> verifyEmail(String token) {
    throw UnsupportedError('Not used by this test');
  }

  @override
  Future<void> requestPasswordReset(String email) {
    throw UnsupportedError('Not used by this test');
  }

  @override
  Future<void> resetPassword({
    required String newPassword,
    required String token,
  }) {
    throw UnsupportedError('Not used by this test');
  }

  @override
  Future<Profile> getCurrentProfile() {
    throw UnsupportedError('Not used by this test');
  }

  @override
  Future<Profile> createProfile({required String displayName, String? bio}) {
    throw UnsupportedError('Not used by this test');
  }

  @override
  Future<Profile> completeWelcome() {
    throw UnsupportedError('Not used by this test');
  }

  @override
  Future<void> redeemReferral({required String code}) {
    throw UnsupportedError('Not used by this test');
  }

  @override
  Future<void> logout() async {}

  @override
  Future<String?> currentToken() async => 'token';
}

class _FakeProfileAvatarRepository implements ProfileAvatarRepository {
  _FakeProfileAvatarRepository(this.profileRepository);

  final _FakeProfileRepository profileRepository;
  final calls = <String>[];
  Completer<void>? uploadGate;
  bool failOnComplete = false;

  @override
  Future<MediaUploadTarget> initUpload({
    required String filename,
    required String mimeType,
    required int sizeBytes,
  }) async {
    calls.add('init:$filename:$mimeType:$sizeBytes');
    return MediaUploadTarget(
      mediaId: 'media-1',
      uploadSessionId: 'session-1',
      uploadEndpoint: '/api/media-assets/media-1/upload-bytes',
      expiresAt: DateTime.utc(2024, 1, 1, 1),
    );
  }

  @override
  Future<void> uploadBytes({
    required MediaUploadTarget target,
    required Uint8List bytes,
    required String contentType,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    calls.add('upload:${target.uploadEndpoint}:$contentType:${bytes.length}');
    onSendProgress?.call(bytes.length, bytes.length);
    await uploadGate?.future;
  }

  @override
  Future<MediaStatus> completeUpload({required String mediaAssetId}) async {
    calls.add('complete:$mediaAssetId');
    if (failOnComplete) {
      throw StateError('technical upload failure');
    }
    return MediaStatus(mediaId: mediaAssetId, state: 'uploaded');
  }

  @override
  Future<MediaStatus> fetchStatus({required String mediaAssetId}) async {
    calls.add('status:$mediaAssetId');
    return MediaStatus(mediaId: mediaAssetId, state: 'ready');
  }

  @override
  Future<Profile> attachAvatar({required String mediaAssetId}) async {
    calls.add('attach:$mediaAssetId');
    profileRepository.profile = profileRepository.profile.copyWith(
      avatarMediaId: mediaAssetId,
      photoUrl: '/api/runtime-media/avatar/$mediaAssetId',
    );
    return profileRepository.profile;
  }
}

Future<void> _pumpProfilePage(
  WidgetTester tester, {
  required _FakeProfileRepository profileRepository,
  required _FakeAuthController authController,
  required _FakeProfileAvatarRepository avatarRepository,
  ProfileAvatarPicker? picker,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => authController),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        profileAvatarPickerProvider.overrideWithValue(
          picker ??
              () async => ProfileAvatarUploadFile(
                name: 'avatar.png',
                mimeType: 'image/png',
                bytes: _avatarBytes,
              ),
        ),
        profileAvatarRepositoryProvider.overrideWithValue(avatarRepository),
        courses_front.myCoursesProvider.overrideWith(
          (ref) async => const [],
        ),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://127.0.0.1:8080',
            subscriptionsEnabled: false,
          ),
        ),
      ],
      child: const MaterialApp(home: ProfilePage()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('profile avatar tap uses shared canonical upload chain', (
    tester,
  ) async {
    final profileRepository = _FakeProfileRepository(_profile());
    final authController = _FakeAuthController(profileRepository);
    final avatarRepository = _FakeProfileAvatarRepository(profileRepository);

    await _pumpProfilePage(
      tester,
      profileRepository: profileRepository,
      authController: authController,
      avatarRepository: avatarRepository,
    );

    await tester.tap(find.bySemanticsLabel('Välj profilbild'));
    await tester.pumpAndSettle();

    expect(avatarRepository.calls, [
      'init:avatar.png:image/png:${_avatarBytes.length}',
      'upload:/api/media-assets/media-1/upload-bytes:image/png:${_avatarBytes.length}',
      'complete:media-1',
      'status:media-1',
      'attach:media-1',
    ]);
    expect(authController.loadSessionCalls, 1);
    expect(profileRepository.updateCalls, 0);
    expect(find.text('Profilbilden är sparad.'), findsWidgets);
    expect(find.bySemanticsLabel('Byt profilbild'), findsOneWidget);
  });

  testWidgets('profile avatar busy state blocks repeated interaction', (
    tester,
  ) async {
    final profileRepository = _FakeProfileRepository(_profile());
    final authController = _FakeAuthController(profileRepository);
    final avatarRepository = _FakeProfileAvatarRepository(profileRepository)
      ..uploadGate = Completer<void>();
    var pickerCalls = 0;

    await _pumpProfilePage(
      tester,
      profileRepository: profileRepository,
      authController: authController,
      avatarRepository: avatarRepository,
      picker: () async {
        pickerCalls += 1;
        return ProfileAvatarUploadFile(
          name: 'avatar.png',
          mimeType: 'image/png',
          bytes: _avatarBytes,
        );
      },
    );

    await tester.tap(find.bySemanticsLabel('Välj profilbild'));
    await tester.pump();

    expect(find.text('Laddar upp profilbild...'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Välj profilbild'), warnIfMissed: false);
    await tester.pump();

    expect(pickerCalls, 1);
    expect(avatarRepository.calls.where((call) => call.startsWith('init:')), hasLength(1));

    avatarRepository.uploadGate!.complete();
    await tester.pumpAndSettle();

    expect(authController.loadSessionCalls, 1);
  });

  testWidgets('profile avatar failure shows Swedish retry copy', (
    tester,
  ) async {
    final profileRepository = _FakeProfileRepository(_profile());
    final authController = _FakeAuthController(profileRepository);
    final avatarRepository = _FakeProfileAvatarRepository(profileRepository)
      ..failOnComplete = true;

    await _pumpProfilePage(
      tester,
      profileRepository: profileRepository,
      authController: authController,
      avatarRepository: avatarRepository,
    );

    await tester.tap(find.bySemanticsLabel('Välj profilbild'));
    await tester.pumpAndSettle();

    expect(find.text('Försök igen'), findsOneWidget);
    expect(find.text('Profilbilden kunde inte sparas.'), findsOneWidget);
    expect(find.text('Försök igen eller välj en annan bild.'), findsOneWidget);
    expect(
      find.text('Kunde inte spara profilbilden. Försök igen.'),
      findsOneWidget,
    );
    expect(authController.loadSessionCalls, 0);
    expect(profileRepository.upda