import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/core/env/app_config.dart';
import 'package:wisdom/core/routing/route_session.dart';
import 'package:wisdom/data/models/certificate.dart';
import 'package:wisdom/data/models/service.dart';
import 'package:wisdom/features/community/application/community_providers.dart';
import 'package:wisdom/features/community/presentation/service_detail_page.dart';
import 'package:wisdom/shared/utils/backend_assets.dart';

import '../helpers/backend_asset_resolver_stub.dart';

void main() {
  const baseService = Service(
    id: 'svc-1',
    title: 'Tarotläsning',
    description: 'Detaljer kring tjänsten.',
    priceCents: 9500,
    currency: 'sek',
    status: 'active',
    durationMinutes: 60,
    requiresCertification: true,
    certifiedArea: 'Tarot',
  );

  Future<void> pumpPage(
    WidgetTester tester, {
    required RouteSessionSnapshot session,
    required List<Certificate> certs,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'https://api.test',
              stripePublishableKey: 'pk_test_123',
              stripeMerchantDisplayName: 'Aveli Test',
              subscriptionsEnabled: false,
            ),
          ),
          backendAssetResolverProvider.overrideWithValue(
            TestBackendAssetResolver(),
          ),
          routeSessionSnapshotProvider.overrideWithValue(session),
          serviceDetailProvider.overrideWith(
            (ref, id) async => const ServiceDetailState(
              service: baseService,
              provider: {'display_name': 'Lärare'},
            ),
          ),
          myCertificatesProvider.overrideWith((ref) async => certs),
        ],
        child: const MaterialApp(home: ServiceDetailPage(id: 'svc-1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows login CTA for gated services when user is logged out', (
    tester,
  ) async {
    const session = RouteSessionSnapshot(
      isAuthenticated: false,
      isTeacher: false,
      isAdmin: false,
    );

    await pumpPage(tester, session: session, certs: const []);

    expect(find.text('Logga in för att boka'), findsOneWidget);
    expect(
      find.text(
        'Logga in för att boka eller för att kontrollera dina certifieringar.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('blocks purchase when user saknar certifiering', (tester) async {
    const session = RouteSessionSnapshot(
      isAuthenticated: true,
      isTeacher: false,
      isAdmin: false,
    );

    await pumpPage(tester, session: session, certs: const []);

    final button = tester.widget<ElevatedButton>(
      find.byType(ElevatedButton).first,
    );
    expect(button.onPressed, isNull);
    expect(find.text('Certifiering krävs'), findsOneWidget);
    expect(
      find.text(
        'Du behöver certifieringen "Tarot" för att boka den här tjänsten.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tillåter köp när användaren har rätt certifiering', (
    tester,
  ) async {
    const session = RouteSessionSnapshot(
      isAuthenticated: true,
      isTeacher: false,
      isAdmin: false,
    );
    const certs = [
      Certificate(
        id: 'cert-1',
        userId: 'user-1',
        title: 'Tarot',
        status: CertificateStatus.verified,
        statusRaw: 'verified',
        createdAt: null,
        updatedAt: null,
      ),
    ];

    await pumpPage(tester, session: session, certs: certs);

    final button = tester.widget<ElevatedButton>(
      find.byType(ElevatedButton).first,
    );
    expect(button.onPressed, isNotNull);
    expect(find.text('Boka/Köp'), findsOneWidget);
  });
}
