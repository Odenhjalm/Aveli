import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/admin/presentation/admin_users_page.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/data/admin_repository.dart';
import '../helpers/test_asset_bundle.dart';

class _MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late _MockAdminRepository repository;

  setUpAll(installTestAssetBundle);

  setUp(() {
    repository = _MockAdminRepository();
  });

  testWidgets('users page shows loading while a role grant is in flight', (
    tester,
  ) async {
    final completer = Completer<void>();
    when(
      () => repository.grantTeacherRole('user-1'),
    ).thenAnswer((_) => completer.future);

    await _pumpUsersPage(tester, repository);

    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-users-user-id-field')),
      'user-1',
    );
    await tester.tap(find.text('Grant teacher role'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('admin-users-user-id-field')),
          )
          .enabled,
      isFalse,
    );

    completer.complete();
    await tester.pumpAndSettle();

    verify(() => repository.grantTeacherRole('user-1')).called(1);
    expect(find.text('Teacher role updated.'), findsOneWidget);
  });

  testWidgets('users page surfaces backend failures for revoke actions', (
    tester,
  ) async {
    when(
      () => repository.revokeTeacherRole('user-1'),
    ).thenThrow(UnexpectedFailure(message: 'Denied'));

    await _pumpUsersPage(tester, repository);

    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-users-user-id-field')),
      'user-1',
    );
    await tester.tap(find.text('Revoke teacher role'));
    await tester.pumpAndSettle();

    verify(() => repository.revokeTeacherRole('user-1')).called(1);
    expect(find.text('Denied'), findsOneWidget);
  });
}

Future<void> _pumpUsersPage(
  WidgetTester tester,
  AdminRepository repository,
) async {
  tester.view.physicalSize = const Size(1280, 960);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: AdminUsersPage()),
    ),
  );

  await tester.pump();
}
