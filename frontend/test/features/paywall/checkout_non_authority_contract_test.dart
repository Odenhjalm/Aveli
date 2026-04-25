import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/deeplinks/deep_link_service.dart';
import 'package:aveli/core/routing/app_router.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/paywall/application/checkout_flow.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';

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

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._handler);

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

class _MockAuthRepository extends Mock implements AuthRepository {}

class _RecordingAuthController extends AuthController {
  _RecordingAuthController._(this._observer)
    : super(_MockAuthRepository(), _observer);

  factory _RecordingAuthController() =>
      _RecordingAuthController._(AuthHttpObserver());

  final AuthHttpObserver _observer;
  int loadSessionCalls = 0;

  @override
  Future<void> loadSession({bool hydrateProfile = true}) async {
    loadSessionCalls += 1;
  }

  @override
  void dispose() {
    _observer.dispose();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('COP-010 checkout launch contract', () {
    test(
      'membership checkout calls the backend subscription endpoint',
      () async {
        final requests = <RequestOptions>[];
        final api = CheckoutApi(
          _recordingClient((options) async {
            requests.add(options);
            expect(options.path, '/api/billing/create-subscription');
            return _jsonResponse({
              'client_secret': 'cs_secret_membership',
              'session_id': 'cs_membership',
              'order_id': 'order_membership',
            });
          }),
        );

        final launch = await api.createMembershipCheckout(interval: 'month');

        expect(requests, hasLength(1));
        expect(requests.single.path, '/api/billing/create-subscription');
        expect(requests.single.data, {'interval': 'month'});
        expect(launch.clientSecret, 'cs_secret_membership');
        expect(launch.sessionId, 'cs_membership');
        expect(launch.orderId, 'order_membership');
      },
    );

    test(
      'course checkout calls the backend course checkout endpoint',
      () async {
        final requests = <RequestOptions>[];
        final api = CheckoutApi(
          _recordingClient((options) async {
            requests.add(options);
            expect(options.path, '/api/checkout/create');
            return _jsonResponse({
              'url': 'https://checkout.test/course',
              'session_id': 'cs_course',
              'order_id': 'order_course',
            });
          }),
        );

        final launch = await api.createCourseCheckout(slug: 'test-kurs');

        expect(requests, hasLength(1));
        expect(requests.single.path, '/api/checkout/create');
        expect(requests.single.data, {'slug': 'test-kurs'});
        expect(launch.url, 'https://checkout.test/course');
        expect(launch.sessionId, 'cs_course');
        expect(launch.orderId, 'order_course');
      },
    );

    test(
      'special offer creation uses the backend execution endpoint',
      () async {
        final requests = <RequestOptions>[];
        final repo = StudioRepository(
          client: _recordingClient((options) async {
            requests.add(options);
            expect(options.path, '/api/teachers/special-offers/execution');
            return _jsonResponse(_specialOfferResponse());
          }),
        );

        final offer = await repo.createSpecialOfferExecution(
          courseIds: const ['course-1', 'course-2'],
          priceAmountCents: 24900,
        );

        expect(requests, hasLength(1));
        expect(requests.single.path, '/api/teachers/special-offers/execution');
        expect(requests.single.data, {
          'course_ids': ['course-1', 'course-2'],
          'price_amount_cents': 24900,
        });
        expect(
          (requests.single.data as Map).containsKey('description'),
          isFalse,
        );
        expect((requests.single.data as Map).containsKey('currency'), isFalse);
        expect((requests.single.data as Map).containsKey('is_active'), isFalse);
        expect(offer.specialOfferId, 'offer-1');
        expect(offer.courseIds, ['course-1', 'course-2']);
      },
    );

    test(
      'special offer image generation uses backend execution endpoints',
      () async {
        final requests = <RequestOptions>[];
        final repo = StudioRepository(
          client: _recordingClient((options) async {
            requests.add(options);
            return _jsonResponse(_specialOfferResponse());
          }),
        );

        await repo.generateSpecialOfferImage('offer-1');
        await repo.regenerateSpecialOfferImage(
          'offer-1',
          confirmOverwrite: true,
        );

        expect(requests, hasLength(2));
        expect(
          requests.first.path,
          '/api/teachers/special-offers/offer-1/execution/generate',
        );
        expect(requests.first.data, isNull);
        expect(
          requests.last.path,
          '/api/teachers/special-offers/offer-1/execution/regenerate',
        );
        expect(requests.last.data, {'confirm_overwrite': true});
      },
    );
  });

  group('COP-010 redirect handling contract', () {
    test('success deep link refreshes backend state before routing', () async {
      final auth = _RecordingAuthController();
      final router = _checkoutRouter();
      addTearDown(router.dispose);
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          appRouterProvider.overrideWithValue(router),
        ],
      );
      addTearDown(container.dispose);

      final handled = await container
          .read(deepLinkServiceProvider)
          .handleUri(
            Uri.parse(
              'aveliapp://checkout/return?session_id=cs_deep&order_id=order_deep',
            ),
          );

      expect(handled, isTrue);
      expect(auth.loadSessionCalls, 1);
      final redirect = container.read(checkoutRedirectStateProvider);
      expect(redirect.status, CheckoutRedirectStatus.processing);
      expect(redirect.sessionId, 'cs_deep');
      expect(redirect.orderId, 'order_deep');
      final uri = router.routeInformationProvider.value.uri;
      expect(uri.path, RoutePath.checkoutSuccess);
      expect(uri.queryParameters['session_id'], 'cs_deep');
      expect(uri.queryParameters['order_id'], 'order_deep');
    });

    test(
      'success deep link without session id does not imply access',
      () async {
        final auth = _RecordingAuthController();
        final router = _checkoutRouter();
        addTearDown(router.dispose);
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith((ref) => auth),
            appRouterProvider.overrideWithValue(router),
          ],
        );
        addTearDown(container.dispose);

        final handled = await container
            .read(deepLinkServiceProvider)
            .handleUri(Uri.parse('aveliapp://checkout/return'));

        expect(handled, isTrue);
        expect(auth.loadSessionCalls, 0);
        final redirect = container.read(checkoutRedirectStateProvider);
        expect(redirect.status, CheckoutRedirectStatus.error);
        expect(redirect.error, 'Betalningssvaret saknar sessions-id.');
        final uri = router.routeInformationProvider.value.uri;
        expect(uri.path, RoutePath.checkoutCancel);
        expect(uri.queryParameters['errored'], '1');
      },
    );

    test(
      'cancel deep link refreshes backend state and stays non-authoritative',
      () async {
        final auth = _RecordingAuthController();
        final router = _checkoutRouter();
        addTearDown(router.dispose);
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith((ref) => auth),
            appRouterProvider.overrideWithValue(router),
          ],
        );
        addTearDown(container.dispose);

        final handled = await container
            .read(deepLinkServiceProvider)
            .handleUri(Uri.parse('aveliapp://checkout/cancel'));

        expect(handled, isTrue);
        expect(auth.loadSessionCalls, 1);
        final redirect = container.read(checkoutRedirectStateProvider);
        expect(redirect.status, CheckoutRedirectStatus.canceled);
        expect(
          router.routeInformationProvider.value.uri.path,
          RoutePath.checkoutCancel,
        );
      },
    );
  });

  group('COP-010 non-authority source contract', () {
    test(
      'ordinary membership checkout uses embedded launch data without hosted URL navigation',
      () {
        final api = _readFrontendSource(
          'lib/features/paywall/data/checkout_api.dart',
        );
        final routePaths = _readFrontendSource(
          'lib/core/routing/route_paths.dart',
        );
        final appRouter = _readFrontendSource(
          'lib/core/routing/app_router.dart',
        );
        final membershipCheckout = _readFrontendSource(
          'lib/features/payments/presentation/subscribe_screen.dart',
        );
        final embeddedWeb = _readFrontendSource(
          'lib/features/payments/presentation/embedded_membership_checkout_surface_web.dart',
        );
        final embeddedHtml = _readFrontendSource(
          'lib/features/payments/presentation/embedded_checkout_html.dart',
        );

        expect(
          routePaths,
          contains("checkoutMembership = '/checkout/membership'"),
        );
        expect(appRouter, contains('path: RoutePath.checkoutMembership'));
        expect(
          appRouter,
          contains(
            'redirect: (context, state) => RoutePath.checkoutMembership',
          ),
        );
        expect(api, contains('MembershipCheckoutLaunch'));
        expect(api, contains("payload['client_secret']"));
        expect(membershipCheckout, contains('class MembershipCheckoutScreen'));
        expect(membershipCheckout, isNot(contains('class SubscribeScreen')));
        expect(
          membershipCheckout,
          contains('EmbeddedMembershipCheckoutSurface'),
        );
        expect(membershipCheckout, contains('launch.clientSecret'));
        expect(membershipCheckout, contains('14 dagar'));
        expect(membershipCheckout, contains('Kortuppgifter krävs'));
        expect(membershipCheckout, contains('_EmbeddedCheckoutViewport'));
        expect(membershipCheckout, contains('_EmbeddedCheckoutFrame'));
        expect(membershipCheckout, contains('BorderRadius.circular(18)'));
        expect(membershipCheckout, contains('withValues(alpha: 0.05)'));
        expect(membershipCheckout, contains('withValues(alpha: 0.12)'));
        expect(membershipCheckout, contains('const SizedBox(width: 42)'));
        expect(membershipCheckout, contains('Expanded(flex: 11'));
        expect(membershipCheckout, contains('EdgeInsets.all(20)'));
        expect(membershipCheckout, isNot(contains('height: 560')));
        expect(embeddedWeb, contains("style.overflowY = 'auto'"));
        expect(embeddedWeb, isNot(contains("style.overflow = 'hidden'")));
        expect(embeddedHtml, contains('overflow-y: auto'));
        expect(embeddedHtml, isNot(contains('overflow: hidden')));
        expect(
          membershipCheckout,
          isNot(contains('router.pushNamed(AppRoute.checkout')),
        );
        expect(membershipCheckout, isNot(contains('launch.url')));
      },
    );

    test(
      'embedded membership success polls backend entry state before routing',
      () {
        final membershipCheckout = _readFrontendSource(
          'lib/features/payments/presentation/subscribe_screen.dart',
        );
        final authController = _readFrontendSource(
          'lib/core/auth/auth_controller.dart',
        );
        final embeddedWeb = _readFrontendSource(
          'lib/features/payments/presentation/embedded_membership_checkout_surface_web.dart',
        );
        final embeddedHtml = _readFrontendSource(
          'lib/features/payments/presentation/embedded_checkout_html.dart',
        );
        final embeddedWebView = _readFrontendSource(
          'lib/features/payments/presentation/embedded_membership_checkout_surface_webview.dart',
        );

        expect(
          membershipCheckout,
          contains('await _waitForBackendMembershipConfirmation(uri);'),
        );
        expect(membershipCheckout, contains('refreshEntryState()'));
        expect(membershipCheckout, contains('!entryState.needsPayment'));
        expect(
          membershipCheckout,
          contains('context.go(RoutePath.createProfile)'),
        );
        expect(membershipCheckout, contains('context.go(RoutePath.welcome)'));
        expect(membershipCheckout, contains('context.go(RoutePath.home)'));
        expect(
          membershipCheckout,
          isNot(contains('context.go(RoutePath.checkoutMembership)')),
        );
        expect(
          authController,
          contains('Future<EntryState?> refreshEntryState()'),
        );
        expect(embeddedWeb, contains("'onComplete'"));
        expect(
          embeddedWeb,
          contains('widget.onCheckoutRedirect(_successUri())'),
        );
        expect(embeddedHtml, contains('onComplete'));
        expect(embeddedHtml, contains('window.location.href = successUri'));
        expect(embeddedWebView, contains('sessionId: widget.sessionId'));
        expect(embeddedWebView, contains('orderId: widget.orderId'));
      },
    );

    test(
      'payment surface has no direct Stripe or Supabase runtime authority',
      () {
        const forbidden = [
          'flutter_stripe',
          'supabase_flutter',
          'Supabase.instance',
          'SupabaseClient',
          'Stripe.instance',
          'PaymentIntent',
          'createToken(',
          'createSource(',
          'createPaymentMethod(',
          'payment_link',
          'paymentLink',
          'app.memberships',
          'canEnterApp = true',
          'membershipActive = true',
          'grantAccess',
        ];

        for (final path in _paymentSurfaceSourceFiles) {
          final source = _readFrontendSource(path);
          for (final token in forbidden) {
            expect(
              source,
              isNot(contains(token)),
              reason: '$path contains $token',
            );
          }
        }
      },
    );

    test(
      'result and WebView handling depend on backend refresh/session state',
      () {
        final result = _readFrontendSource(
          'lib/features/paywall/presentation/checkout_result_page.dart',
        );
        final webView = _readFrontendSource(
          'lib/features/paywall/presentation/checkout_webview_page.dart',
        );
        final deepLinks = _readFrontendSource(
          'lib/core/deeplinks/deep_link_service.dart',
        );

        expect(result, contains('await authController.loadSession();'));
        expect(
          result,
          contains('Åtkomst visas först när köpet har bekräftats.'),
        );
        expect(
          webView,
          contains('_hasSessionId(uri) || _hasBackendCheckoutSession()'),
        );
        expect(webView, contains('await _refreshSession();'));
        expect(
          deepLinks,
          contains(
            'await _ref.read(authControllerProvider.notifier).loadSession();',
          ),
        );
        expect(
          deepLinks,
          isNot(contains('status: CheckoutRedirectStatus.success')),
        );
      },
    );

    test('special offer execution remains backend-owned and non-entitling', () {
      final source = _readFrontendSource(
        'lib/features/studio/presentation/teacher_home_page.dart',
      );

      expect(source, contains('createSpecialOfferExecution('));
      expect(source, contains('generateSpecialOfferImage('));
      expect(source, contains('regenerateSpecialOfferImage('));
      expect(source, isNot(contains('AppRoute.checkout')));
      expect(source, isNot(contains("checkout['payment_link']")));
      expect(source, isNot(contains('payment_link')));
      expect(source, isNot(contains('app.memberships')));
      expect(source, isNot(contains('membershipActive')));
      expect(source, isNot(contains('canEnterApp')));
      expect(source, isNot(contains('grantAccess')));
    });

    test(
      'special offer authoring UI does not expose removed bundle fields',
      () {
        final pageSource = _readFrontendSource(
          'lib/features/studio/presentation/teacher_home_page.dart',
        );
        final repoSource = _readFrontendSource(
          'lib/features/studio/data/studio_repository.dart',
        );

        expect(pageSource, isNot(contains('_descriptionController')));
        expect(pageSource, isNot(contains('_isActive')));
        expect(pageSource, isNot(contains("bundle['description']")));
        expect(pageSource, isNot(contains("bundle['is_active']")));
        expect(repoSource, isNot(contains('/api/teachers/course-bundles')));
        expect(repoSource, isNot(contains("'description'")));
        expect(repoSource, isNot(contains("'currency'")));
        expect(repoSource, isNot(contains("'is_active'")));
      },
    );

    test('special offer failures do not expose technical exception text', () {
      final source = _readFrontendSource(
        'lib/features/studio/presentation/teacher_home_page.dart',
      );

      expect(source, contains('catch (_)'));
      expect(source, isNot(contains(r'Kunde inte spara paket: $e')));
      expect(source, isNot(contains(r'Kunde inte starta betalning: $e')));
      expect(source, isNot(contains(r'Kunde inte hämta kurser: $error')));
      expect(source, isNot(contains(r'Kunde inte läsa paket: $error')));
    });
  });
}

const _paymentSurfaceSourceFiles = [
  'lib/features/payments/application/billing_providers.dart',
  'lib/features/payments/data/billing_api.dart',
  'lib/features/payments/presentation/embedded_checkout_html.dart',
  'lib/features/payments/presentation/embedded_membership_checkout_surface.dart',
  'lib/features/payments/presentation/embedded_membership_checkout_surface_stub.dart',
  'lib/features/payments/presentation/embedded_membership_checkout_surface_web.dart',
  'lib/features/payments/presentation/embedded_membership_checkout_surface_webview.dart',
  'lib/features/payments/presentation/paywall_prompt.dart',
  'lib/features/payments/presentation/subscribe_screen.dart',
  'lib/features/paywall/application/checkout_flow.dart',
  'lib/features/paywall/application/pricing_providers.dart',
  'lib/features/paywall/data/checkout_api.dart',
  'lib/features/paywall/data/course_pricing_api.dart',
  'lib/features/paywall/presentation/checkout_result_page.dart',
  'lib/features/paywall/presentation/checkout_webview_page.dart',
  'lib/features/studio/data/studio_repository.dart',
  'lib/features/studio/presentation/teacher_home_page.dart',
  'lib/core/deeplinks/deep_link_service.dart',
];

ApiClient _recordingClient(
  Future<ResponseBody> Function(RequestOptions options) handler,
) {
  final client = ApiClient(
    baseUrl: 'http://localhost',
    tokenStorage: _FakeTokenStorage(),
  );
  client.raw.httpClientAdapter = _RecordingAdapter(handler);
  return client;
}

ResponseBody _jsonResponse(Map<String, Object?> payload) {
  return ResponseBody.fromString(
    jsonEncode(payload),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

Map<String, Object?> _specialOfferResponse() {
  return {
    'special_offer_id': 'offer-1',
    'active_output_id': null,
    'active_media_asset_id': null,
    'state_hash': 'hash-1',
    'attempt_id': null,
    'status': 'draft',
    'text_id': null,
    'source_count': 2,
    'overwrite_applied': false,
    'image_current': false,
    'image_required': true,
    'price_amount_cents': 24900,
    'course_ids': ['course-1', 'course-2'],
    'image': null,
  };
}

GoRouter _checkoutRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: RoutePath.checkoutSuccess,
        builder: (_, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.checkoutCancel,
        builder: (_, _) => const SizedBox.shrink(),
      ),
    ],
  );
}

String _readFrontendSource(String frontendRelativePath) {
  final candidates = [
    File(frontendRelativePath),
    File('frontend/$frontendRelativePath'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }
  fail(
    'Source file not found in allowed COP-010 surface: $frontendRelativePath',
  );
}
