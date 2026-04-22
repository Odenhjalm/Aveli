import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/data/admin_repository.dart';
import 'package:aveli/features/community/presentation/admin_page.dart';
import 'package:aveli/features/media_control_plane/admin/media_control_plane_providers.dart';
import 'package:aveli/features/media_control_plane/data/media_control_plane_repository.dart';
import '../helpers/admin_test_fixtures.dart';
import '../helpers/test_asset_bundle.dart';

class _MockAdminRepository extends Mock implements AdminRepository {}

class _MockMediaControlPlaneRepository extends Mock
    implements MediaControlPlaneRepository {}

void main() {
  late _MockAdminRepository adminRepository;
  late _MockMediaControlPlaneRepository mediaRepository;

  setUpAll(installTestAssetBundle);

  setUp(() {
    adminRepository = _MockAdminRepository();
    mediaRepository = _MockMediaControlPlaneRepository();
    when(
      () => adminRepository.fetchSettings(),
    ).thenAnswer((_) async => sampleAdminSettingsPayload());
    when(
      () => mediaRepository.fetchHealth(),
    ).thenAnswer((_) async => sampleMediaHealthPayload());
  });

  testWidgets('wide control room renders all cards and disabled nav items', (
    tester,
  ) async {
    await _pumpAdminPage(
      tester,
      adminRepository: adminRepository,
      mediaRepository: mediaRepository,
      size: const Size(1440, 1080),
    );

    expect(
      find.byKey(const ValueKey<String>('admin-nav-control-room')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('admin-nav-disabled-courses')),
      findsOneWidget,
    );
    expect(find.text('All systems nominal'), findsOneWidget);
    expect(find.text('42 total users'), findsOneWidget);

    for (final id in const [
      'notifications',
      'auth-system',
      'learning-system',
      'system-health',
      'payments',
      'media-control-plane',
    ]) {
      expect(find.byKey(ValueKey<String>('admin-card-$id')), findsOneWidget);
    }
  });

  testWidgets('narrow control room keeps cards and disabled nav chips', (
    tester,
  ) async {
    await _pumpAdminPage(
      tester,
      adminRepository: adminRepository,
      mediaRepository: mediaRepository,
      size: const Size(720, 1280),
    );

    expect(
      find.byKey(const ValueKey<String>('admin-nav-control-room')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('admin-nav-disabled-payments')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('admin-card-system-health')),
      findsOneWidget,
    );
    expect(
      find.text('Status OK with 2 capabilities and 2 shortcuts.'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpAdminPage(
  WidgetTester tester, {
  required AdminRepository adminRepository,
  required MediaControlPlaneRepository mediaRepository,
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(adminRepository),
        mediaControlPlaneRepositoryProvider.overrideWithValue(mediaRepository),
      ],
      child: const MaterialApp(home: AdminPage()),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
