import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/data/models/seminar.dart';
import 'package:wisdom/data/repositories/seminar_repository.dart';
import 'package:wisdom/features/home/application/livekit_controller.dart';
import 'package:wisdom/features/seminars/application/seminar_providers.dart';
import 'package:wisdom/features/seminars/presentation/seminar_detail_page.dart';
import 'package:wisdom/features/seminars/presentation/seminar_join_page.dart';
import 'package:wisdom/shared/widgets/gradient_button.dart';
import 'package:wisdom/core/env/app_config.dart';
import 'package:wisdom/shared/utils/backend_assets.dart';

class _TestAssetResolver extends BackendAssetResolver {
  _TestAssetResolver() : super('');

  @override
  ImageProvider<Object> imageProvider(String assetPath, {double scale = 1.0}) {
    return const AssetImage('assets/images/bakgrund.png');
  }
}

Future<void> _pumpFor(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;

  testWidgets('Host studio and participant join show live session state', (
    tester,
  ) async {
    final now = DateTime.now();
    final seminar = Seminar(
      id: 'sem-live',
      hostId: 'host-1',
      title: 'Integration QA',
      description: 'Covers host + participant flows',
      status: SeminarStatus.live,
      scheduledAt: now.add(const Duration(minutes: 10)),
      durationMinutes: 45,
      livekitRoom: 'room-123',
      livekitMetadata: const {},
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now,
    );
    final liveSession = SeminarSession(
      id: 'session-live',
      seminarId: seminar.id,
      status: SeminarSessionStatus.live,
      scheduledAt: now.subtract(const Duration(minutes: 5)),
      startedAt: now.subtract(const Duration(minutes: 2)),
      endedAt: null,
      livekitRoom: seminar.livekitRoom,
      livekitSid: 'LK-SID',
      metadata: const {'started_by': 'host-1'},
      createdAt: now.subtract(const Duration(hours: 1)),
      updatedAt: now,
    );
    final attendee = SeminarRegistration(
      seminarId: seminar.id,
      userId: 'participant-1',
      role: 'participant',
      inviteStatus: 'registered',
      joinedAt: null,
      leftAt: null,
      livekitIdentity: null,
      livekitParticipantSid: null,
      createdAt: now.subtract(const Duration(minutes: 1)),
    );
    final detail = SeminarDetail(
      seminar: seminar,
      sessions: [liveSession],
      attendees: [attendee],
      recordings: const [],
    );

    final fakeRepository = _FakeSeminarRepository(
      hostSeminars: [seminar],
      detail: detail,
    );

    _TrackingLiveSessionController.reset();

    final overrides = [
      appConfigProvider.overrideWithValue(
        const AppConfig(
          apiBaseUrl: 'http://localhost',
          stripePublishableKey: 'pk_test',
          stripeMerchantDisplayName: 'Aveli',
          subscriptionsEnabled: false,
        ),
      ),
      backendAssetResolverProvider.overrideWithValue(
        _TestAssetResolver(),
      ),
      seminarRepositoryProvider.overrideWithValue(fakeRepository),
      hostSeminarsProvider.overrideWith(
        (ref) async => fakeRepository.hostSeminars,
      ),
      seminarDetailProvider(
        seminar.id,
      ).overrideWith((ref) async => fakeRepository.detail),
      publicSeminarDetailProvider(
        seminar.id,
      ).overrideWith((ref) async => fakeRepository.detail),
      liveSessionControllerProvider.overrideWith(
        _TrackingLiveSessionController.new,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: SeminarDetailPage(seminarId: seminar.id)),
      ),
    );
    await _pumpFor(tester);

    expect(find.text('Session live'), findsOneWidget);
    expect(find.text('Avsluta'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: SeminarJoinPage(seminarId: seminar.id)),
      ),
    );
    await _pumpFor(tester);

    expect(find.text('Status: LIVE'), findsOneWidget);
    final joinFinder = find.widgetWithText(GradientButton, 'Anslut');
    expect(joinFinder, findsOneWidget);
    final joinButton = tester.widget<GradientButton>(joinFinder);
    expect(joinButton.onPressed, isNotNull);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: SeminarDetailPage(seminarId: seminar.id)),
      ),
    );
    await _pumpFor(tester);

    await tester.tap(find.text('Avsluta'));
    await _pumpFor(tester);

    expect(fakeRepository.endSessionCalls, 1);
    expect(_TrackingLiveSessionController.disconnectCount, 1);
  });
}

class _TrackingLiveSessionController extends LiveSessionController {
  static int disconnectCount = 0;

  static void reset() {
    disconnectCount = 0;
  }

  @override
  LiveSessionState build() => const LiveSessionState();

  @override
  Future<void> disconnect() async {
    disconnectCount += 1;
    state = const LiveSessionState();
  }
}

class _FakeSeminarRepository implements SeminarRepository {
  _FakeSeminarRepository({
    required List<Seminar> hostSeminars,
    required SeminarDetail detail,
  }) : _hostSeminars = hostSeminars,
       _detail = detail;

  final List<Seminar> _hostSeminars;
  SeminarDetail _detail;
  int endSessionCalls = 0;

  List<Seminar> get hostSeminars => _hostSeminars;
  SeminarDetail get detail => _detail;

  @override
  Future<List<Seminar>> listHostSeminars() async => _hostSeminars;

  @override
  Future<SeminarDetail> getSeminarDetail(String id) async => _detail;

  @override
  Future<SeminarSession> endSession(
    String seminarId,
    String sessionId, {
    String? reason,
  }) async {
    endSessionCalls += 1;
    final session = _detail.sessions.firstWhere((item) => item.id == sessionId);
    final endedAt = DateTime.now();
    final updatedSession = SeminarSession(
      id: session.id,
      seminarId: session.seminarId,
      status: SeminarSessionStatus.ended,
      scheduledAt: session.scheduledAt,
      startedAt: session.startedAt,
      endedAt: endedAt,
      livekitRoom: session.livekitRoom,
      livekitSid: session.livekitSid,
      metadata: session.metadata,
      createdAt: session.createdAt,
      updatedAt: endedAt,
    );
    _detail = SeminarDetail(
      seminar: _detail.seminar,
      sessions: [updatedSession],
      attendees: _detail.attendees,
      recordings: _detail.recordings,
    );
    return updatedSession;
  }

  @override
  Future<SeminarSessionStartResult> startSession(
    String seminarId, {
    String? sessionId,
    int? maxParticipants,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Seminar> createSeminar({
    required String title,
    String? description,
    DateTime? scheduledAt,
    int? durationMinutes,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Seminar> updateSeminar({
    required String id,
    String? title,
    String? description,
    DateTime? scheduledAt,
    int? durationMinutes,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Seminar> publishSeminar(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Seminar> cancelSeminar(String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<Seminar>> listPublicSeminars() {
    throw UnimplementedError();
  }

  @override
  Future<SeminarDetail> getPublicSeminar(String id) async => _detail;

  @override
  Future<SeminarRegistration> registerForSeminar(String id) {
    throw UnimplementedError();
  }

  @override
  Future<void> unregisterFromSeminar(String id) {
    throw UnimplementedError();
  }

  @override
  Future<SeminarRecording> reserveRecording(
    String seminarId, {
    String? sessionId,
    String? extension,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SeminarRegistration> grantSeminarAccess({
    required String seminarId,
    required String userId,
    String role = 'participant',
    String inviteStatus = 'accepted',
  }) async {
    final registration = SeminarRegistration(
      seminarId: seminarId,
      userId: userId,
      role: role,
      inviteStatus: inviteStatus,
      createdAt: DateTime.now(),
      joinedAt: null,
      leftAt: null,
      livekitIdentity: null,
      livekitParticipantSid: null,
    );
    final attendees = <SeminarRegistration>[
      ..._detail.attendees.where(
        (attendee) => attendee.userId != userId || attendee.seminarId != seminarId,
      ),
      registration,
    ];
    _detail = SeminarDetail(
      seminar: _detail.seminar,
      sessions: _detail.sessions,
      attendees: attendees,
      recordings: _detail.recordings,
    );
    return registration;
  }

  @override
  Future<void> revokeSeminarAccess({
    required String seminarId,
    required String userId,
  }) async {
    final attendees = _detail.attendees.where(
      (attendee) => attendee.userId != userId || attendee.seminarId != seminarId,
    );
    _detail = SeminarDetail(
      seminar: _detail.seminar,
      sessions: _detail.sessions,
      attendees: attendees.toList(),
      recordings: _detail.recordings,
    );
  }
}
