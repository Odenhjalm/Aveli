import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/data/admin_repository.dart';
import 'package:aveli/features/community/presentation/admin_settings_page.dart';
import '../helpers/admin_test_fixtures.dart';
import '../helpers/test_asset_bundle.dart';

class _MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late _MockAdminRepository repository;

  setUpAll(installTestAssetBundle);

  setUp(() {
    repository = _MockAdminRepository();
    when(
      () => repository.fetchSettings(),
    ).thenAnswer((_) async => sampleAdminSettingsPayload());
  });

  testWidgets('system page renders live metrics and teacher priorities', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [adminRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AdminSettingsPage()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('42 users, 7 teachers, 12 courses'), findsOneWidget);
    expect(find.text('Revenue (30d)'), findsOneWidget);
    expect(find.text('820.00 kr'), findsOneWidget);
    expect(find.text('Teacher priority queue'), findsOneWidget);
    expect(find.text('Aveli Teacher'), findsOneWidget);
    expect(find.text('1/3 published courses'), findsOneWidget);
    expect(find.text('Needs review before launch.'), findsOneWidget);
  });
}
