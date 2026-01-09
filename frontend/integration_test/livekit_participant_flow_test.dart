import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import 'package:aveli/data/models/seminar.dart';
import 'package:aveli/features/seminars/application/seminar_providers.dart';
import 'package:aveli/features/seminars/presentation/seminar_discover_page.dart';
import 'package:aveli/features/seminars/presentation/seminar_join_page.dart';
import 'package:aveli/features/home/application/livekit_controller.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

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

class _FakeLiveSessionController extends LiveSessionController {
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
  Future<void> disconnect() async {}

  @override
  Future<void> setScreenShareEnabled(bool enable) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;

  testWidgets('Seminar list shows live and scheduled badges', (tester) async {
    final liveSeminar = Seminar(
      id: 'live-1',
      hostId: 'host',
      title: 'Live Breathwork',
      description: 'Guided session',
      status: SeminarStatus.live,
      scheduledAt: DateTime.now().add(const Duration(minutes: 5)),
      durationMinutes: 45,
      livekitRoom: 'room',
      livekitMetadata: const {},
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final scheduledSeminar = Seminar(
      id: 'sched-1',
      hostId: liveSeminar.hostId,
      title: 'Upcoming Workshop',
      description: 'Starting later',
      status: SeminarStatus.scheduled,
      scheduledAt: DateTime.now().add(const Duration(hours: 2)),
      durationMinutes: liveSeminar.durationMinutes,
      livekitRoom: liveSeminar.livekitRoom,
      livekitMetadata: const {},
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
          publicSeminarsProvider.overrideWith(
            (ref) async => [liveSeminar, scheduledSeminar],
          ),
        ],
        child: const MaterialApp(home: SeminarDiscoverPage()),
      ),
    );

    await _pumpFor(tester);

    expect(find.textContaining('LIVE'), findsOneWidget);
    expect(find.textContaining('Planerat'), findsWidgets);
    expect(
      find.textContaining(
        DateFormat('yyyy-MM-dd').format(liveSeminar.scheduledAt!),
      ),
      findsWidgets,
    );
  });

  testWidgets('Join page disables join button until session live', (
    tester,
  ) async {
    final seminar = Seminar(
      id: 'future-1',
      hostId: 'host',
      title: 'Future Seminar',
      description: 'Not yet live',
      status: SeminarStatus.scheduled,
      scheduledAt: DateTime.now().add(const Duration(hours: 1)),
      durationMinutes: 30,
      livekitRoom: null,
      livekitMetadata: const {},
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final detail = SeminarDetail(
      seminar: seminar,
      sessions: const [],
      attendees: const [],
      recordings: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
          publicSeminarDetailProvider(
            seminar.id,
          ).overrideWith((ref) async => detail),
          liveSessionControllerProvider.overrideWith(
            _FakeLiveSessionController.new,
          ),
        ],
        child: MaterialApp(home: SeminarJoinPage(seminarId: seminar.id)),
      ),
    );

    await _pumpFor(tester);

    final joinButton = find.widgetWithText(GradientButton, 'Anslut');
    expect(joinButton, findsOneWidget);
    final buttonWidget = tester.widget<GradientButton>(joinButton);
    expect(buttonWidget.onPressed, isNull);
    expect(find.textContaining('Knappen blir aktiv'), findsOneWidget);
  });
}
