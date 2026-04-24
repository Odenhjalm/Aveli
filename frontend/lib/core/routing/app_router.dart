import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/bootstrap/auth_boot_page.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/not_found_page.dart';
import 'package:aveli/core/routing/route_access.dart';
import 'package:aveli/core/routing/route_manifest.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/core/routing/route_session.dart';
import 'package:aveli/core/routing/route_extras.dart';
import 'package:aveli/features/auth/presentation/forgot_password_page.dart';
import 'package:aveli/features/auth/presentation/login_page.dart';
import 'package:aveli/features/auth/presentation/new_password_page.dart';
import 'package:aveli/features/auth/presentation/settings_page.dart';
import 'package:aveli/features/auth/presentation/signup_page.dart';
import 'package:aveli/features/auth/presentation/verify_email_page.dart';
import 'package:aveli/features/admin/presentation/admin_users_page.dart';
import 'package:aveli/features/community/presentation/admin_page.dart';
import 'package:aveli/features/community/presentation/admin_settings_page.dart';
import 'package:aveli/features/community/presentation/community_page.dart';
import 'package:aveli/features/home/presentation/home_dashboard_page.dart';
import 'package:aveli/features/media_control_plane/admin/media_control_dashboard.dart';
import 'package:aveli/features/community/presentation/profile_page.dart'
    as community_profile;
import 'package:aveli/features/community/presentation/profile_view_page.dart';
import 'package:aveli/features/community/presentation/service_detail_page.dart';
import 'package:aveli/features/community/presentation/tarot_page.dart';
import 'package:aveli/features/community/presentation/teacher_profile_page.dart';
import 'package:aveli/features/profile/presentation/my_subscription_page.dart';
import 'package:aveli/features/courses/presentation/course_intro_page.dart';
import 'package:aveli/features/courses/presentation/course_intro_redirect_page.dart';
import 'package:aveli/features/courses/presentation/course_catalog_page.dart';
import 'package:aveli/features/courses/presentation/course_page.dart';
import 'package:aveli/features/courses/presentation/lesson_page.dart';
import 'package:aveli/features/landing/presentation/landing_page.dart';
import 'package:aveli/features/landing/presentation/legal/privacy_page.dart';
import 'package:aveli/features/landing/presentation/legal/terms_page.dart';
import 'package:aveli/features/messages/presentation/chat_page.dart';
import 'package:aveli/features/messages/presentation/messages_page.dart';
import 'package:aveli/features/onboarding/onboarding_profile_page.dart';
import 'package:aveli/features/payments/presentation/booking_page.dart';
import 'package:aveli/features/payments/presentation/subscribe_screen.dart';
import 'package:aveli/features/onboarding/welcome_page.dart';
import 'package:aveli/features/paywall/presentation/checkout_result_page.dart';
import 'package:aveli/features/paywall/presentation/checkout_webview_page.dart';
import 'package:aveli/features/studio/presentation/course_editor_page.dart';
import 'package:aveli/features/studio/presentation/profile_media_page.dart';
import 'package:aveli/features/studio/presentation/studio_page.dart';
import 'package:aveli/features/studio/presentation/teacher_home_page.dart';
import 'package:aveli/shared/utils/slug_validator.dart';

class AppRouterNotifier extends ChangeNotifier {
  AppRouterNotifier(this.ref) {
    _sessionSub = ref.listen<RouteSessionSnapshot>(
      routeSessionSnapshotProvider,
      (previous, next) => notifyListeners(),
    );
  }

  final Ref ref;
  late final ProviderSubscription<RouteSessionSnapshot> _sessionSub;

  RouteSessionSnapshot get session => ref.read(routeSessionSnapshotProvider);

  String? handleRedirect(GoRouterState state) {
    if (state.matchedLocation == RoutePath.subscribe) {
      return RoutePath.checkoutMembership;
    }

    final meta = _resolveRouteMeta(state);
    final session = ref.read(routeSessionSnapshotProvider);
    final isBootRoute = state.matchedLocation == RoutePath.boot;

    if (session.isEntryStateLoading) {
      if (isBootRoute) return null;
      return _bootRedirect(state);
    }

    if (!session.hasEntryState) {
      if (meta.level == RouteAccessLevel.public && !isBootRoute) {
        return null;
      }
      if (isBootRoute) {
        final redirectTarget = _sanitizeRedirect(
          state.uri.queryParameters['redirect'],
        );
        return state.namedLocation(
          AppRoute.login,
          queryParameters: {
            if (redirectTarget != null) 'redirect': redirectTarget,
          },
        );
      }
      return _loginRedirect(state);
    }

    if (session.canEnterApp) {
      if (isBootRoute || meta.redirectAuthed || _isPreEntryRoute(state)) {
        return _resolveDefaultAuthedTarget();
      }
      return null;
    }

    final referralCode = state.uri.queryParameters['referral_code'];
    final preEntryTarget = _resolvePreEntryTarget(
      session,
      referralCode: referralCode,
    );
    if (_isAllowedPreEntryRoute(state, session, referralCode: referralCode)) {
      return null;
    }

    return preEntryTarget;
  }

  @override
  void dispose() {
    _sessionSub.close();
    super.dispose();
  }
}

const RouteAccessMeta _defaultPrivateMeta = RouteAccessMeta(
  level: RouteAccessLevel.authenticated,
);

RouteAccessMeta _resolveRouteMeta(GoRouterState state) {
  final routeName = state.name;
  if (routeName != null) {
    final meta = _routeAccessMeta[routeName];
    if (meta != null) return meta;
  }
  final pathMeta = _staticPathAccessMeta[state.uri.path];
  return pathMeta ?? _defaultPrivateMeta;
}

String? _sanitizeRedirect(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return raw.startsWith('/') ? raw : null;
}

String _bootRedirect(GoRouterState state) {
  return state.namedLocation(
    AppRoute.boot,
    queryParameters: {'redirect': state.uri.toString()},
  );
}

String _loginRedirect(GoRouterState state) {
  if (state.matchedLocation == RoutePath.login) {
    return RoutePath.login;
  }
  return state.namedLocation(
    AppRoute.login,
    queryParameters: {'redirect': state.uri.toString()},
  );
}

String _resolveDefaultAuthedTarget() {
  return RoutePath.home;
}

String _resolvePreEntryTarget(
  RouteSessionSnapshot session, {
  String? referralCode,
}) {
  final hasReferralContext = referralCode?.trim().isNotEmpty == true;
  if (hasReferralContext && session.needsCreateProfile) {
    return Uri(
      path: RoutePath.createProfile,
      queryParameters: {'referral_code': referralCode!.trim()},
    ).toString();
  }
  if (session.needsPayment) {
    return RoutePath.checkoutMembership;
  }
  if (session.needsWelcome) {
    return RoutePath.welcome;
  }
  if (session.needsCreateProfile) {
    return RoutePath.createProfile;
  }
  return RoutePath.login;
}

bool _isPreEntryRoute(GoRouterState state) {
  return _preEntryPaths.contains(state.matchedLocation);
}

bool _isAllowedPreEntryRoute(
  GoRouterState state,
  RouteSessionSnapshot session, {
  String? referralCode,
}) {
  final location = state.matchedLocation;
  final hasReferralContext = referralCode?.trim().isNotEmpty == true;
  if (hasReferralContext &&
      session.needsCreateProfile &&
      location == RoutePath.createProfile) {
    return true;
  }
  if (session.needsPayment) {
    return _paymentPreEntryPaths.contains(location);
  }
  if (session.needsWelcome) {
    return _welcomePreEntryPaths.contains(location);
  }
  if (session.needsCreateProfile) {
    return _createProfilePreEntryPaths.contains(location);
  }
  return location == RoutePath.login || location == RoutePath.signup;
}

const Set<String> _createProfilePreEntryPaths = {RoutePath.createProfile};

const Set<String> _welcomePreEntryPaths = {
  RoutePath.welcome,
  RoutePath.courseIntro,
};

const Set<String> _paymentPreEntryPaths = {
  RoutePath.checkoutMembership,
  RoutePath.profileSubscription,
  RoutePath.checkout,
  RoutePath.checkoutReturn,
  RoutePath.checkoutHostedCancel,
  RoutePath.checkoutSuccess,
  RoutePath.checkoutCancel,
};

const Set<String> _preEntryPaths = {
  ..._createProfilePreEntryPaths,
  ..._welcomePreEntryPaths,
  ..._paymentPreEntryPaths,
};

final Map<String, RouteAccessMeta> _routeAccessMeta = {
  for (final entry in routeManifest)
    entry.name: RouteAccessMeta(
      level: entry.access,
      redirectAuthed: entry.redirectAuthed,
    ),
};

final Map<String, RouteAccessMeta> _staticPathAccessMeta = {
  for (final entry in routeManifest.where((entry) => !entry.hasDynamicSegment))
    entry.path: RouteAccessMeta(
      level: entry.access,
      redirectAuthed: entry.redirectAuthed,
    ),
};

final appRouterNotifierProvider = Provider<AppRouterNotifier>((ref) {
  final notifier = AppRouterNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(appRouterNotifierProvider);
  final initialSession = ref.read(routeSessionSnapshotProvider);
  final initialLocation = initialSession.canEnterApp
      ? RoutePath.home
      : RoutePath.boot;
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: notifier,
    redirect: (context, state) => notifier.handleRedirect(state),
    errorBuilder: (context, state) => const NotFoundPage(),
    routes: [
      GoRoute(
        path: RoutePath.boot,
        name: AppRoute.boot,
        builder: (context, state) => const AuthBootPage(),
      ),
      GoRoute(
        path: RoutePath.login,
        name: AppRoute.login,
        builder: (context, state) =>
            LoginPage(redirectPath: state.uri.queryParameters['redirect']),
      ),
      GoRoute(
        path: RoutePath.signup,
        name: AppRoute.signup,
        builder: (context, state) => SignupPage(
          initialEmail: state.uri.queryParameters['email'],
          redirectPath: state.uri.queryParameters['redirect'],
        ),
      ),
      GoRoute(
        path: RoutePath.verifyEmail,
        name: AppRoute.verifyEmail,
        builder: (context, state) =>
            VerifyEmailPage(token: state.uri.queryParameters['token']),
      ),
      GoRoute(
        path: RoutePath.forgotPassword,
        name: AppRoute.forgotPassword,
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: RoutePath.resetPassword,
        name: AppRoute.resetPassword,
        builder: (context, state) =>
            NewPasswordPage(token: state.uri.queryParameters['token']),
      ),
      GoRoute(
        path: RoutePath.landingRoot,
        name: AppRoute.landingRoot,
        builder: (context, state) => const LandingPage(),
      ),
      GoRoute(
        path: RoutePath.landing,
        name: AppRoute.landing,
        builder: (context, state) => const LandingPage(),
      ),
      GoRoute(
        path: RoutePath.home,
        name: AppRoute.home,
        builder: (context, state) => const HomeDashboardPage(),
      ),
      GoRoute(
        path: RoutePath.courseIntro,
        name: AppRoute.courseIntro,
        builder: (context, state) => const CourseIntroPage(),
      ),
      GoRoute(
        path: RoutePath.courseCatalog,
        name: AppRoute.courseCatalog,
        builder: (context, state) => const CourseCatalogPage(),
      ),
      GoRoute(
        path: RoutePath.course,
        name: AppRoute.course,
        builder: (context, state) {
          final slug = state.pathParameters['slug']!;
          if (!isValidSlug(slug)) {
            debugPrint('[ROUTER_GUARD] Invalid slug: $slug');
            return const SizedBox.shrink();
          }
          return CoursePage(slug: slug);
        },
      ),
      GoRoute(
        path: RoutePath.lesson,
        name: AppRoute.lesson,
        builder: (context, state) =>
            LessonPage(lessonId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePath.courseIntroRedirect,
        name: AppRoute.courseIntroRedirect,
        builder: (context, state) => const CourseIntroRedirectPage(),
      ),
      GoRoute(
        path: RoutePath.messages,
        name: AppRoute.messages,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! MessagesRouteArgs) {
            return const NotFoundPage();
          }
          return MessagesPage(kind: extra.kind, id: extra.id);
        },
      ),
      GoRoute(
        path: RoutePath.directMessage,
        name: AppRoute.directMessage,
        builder: (context, state) => const ChatPage(),
      ),
      GoRoute(
        path: RoutePath.profile,
        name: AppRoute.profile,
        builder: (context, state) => const community_profile.ProfilePage(),
      ),
      GoRoute(
        path: RoutePath.createProfile,
        name: AppRoute.createProfile,
        builder: (context, state) => OnboardingProfilePage(
          referralCode: state.uri.queryParameters['referral_code'],
        ),
      ),
      GoRoute(
        path: RoutePath.welcome,
        name: AppRoute.welcome,
        builder: (context, state) => const WelcomePage(),
      ),
      GoRoute(
        path: RoutePath.profileSubscription,
        name: AppRoute.profileSubscription,
        builder: (context, state) => const MySubscriptionPage(),
      ),
      GoRoute(
        path: RoutePath.checkout,
        name: AppRoute.checkout,
        builder: (context, state) {
          final url = state.extra;
          if (url is! String || url.isEmpty) {
            return const NotFoundPage();
          }
          return CheckoutWebViewPage(url: url);
        },
      ),
      GoRoute(
        path: RoutePath.checkoutMembership,
        name: AppRoute.checkoutMembership,
        builder: (context, state) => const MembershipCheckoutScreen(),
      ),
      GoRoute(
        path: RoutePath.checkoutReturn,
        name: AppRoute.checkoutReturn,
        builder: (context, state) => const CheckoutResultPage(success: true),
      ),
      GoRoute(
        path: RoutePath.checkoutHostedCancel,
        name: AppRoute.checkoutHostedCancel,
        builder: (context, state) => const CheckoutResultPage(success: false),
      ),
      GoRoute(
        path: RoutePath.checkoutSuccess,
        name: AppRoute.checkoutSuccess,
        builder: (context, state) => const CheckoutResultPage(success: true),
      ),
      GoRoute(
        path: RoutePath.checkoutCancel,
        name: AppRoute.checkoutCancel,
        builder: (context, state) => const CheckoutResultPage(success: false),
      ),
      GoRoute(
        path: RoutePath.profileView,
        name: AppRoute.profileView,
        builder: (context, state) =>
            ProfileViewPage(userId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePath.teacherProfile,
        name: AppRoute.teacherProfile,
        builder: (context, state) =>
            TeacherProfilePage(userId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePath.serviceDetail,
        name: AppRoute.serviceDetail,
        builder: (context, state) =>
            ServiceDetailPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePath.tarot,
        name: AppRoute.tarot,
        builder: (context, state) => const TarotPage(),
      ),
      GoRoute(
        path: RoutePath.admin,
        name: AppRoute.admin,
        builder: (context, state) => const AdminPage(),
      ),
      GoRoute(
        path: RoutePath.adminUsers,
        name: AppRoute.adminUsers,
        builder: (context, state) => const AdminUsersPage(),
      ),
      GoRoute(
        path: RoutePath.adminMedia,
        name: AppRoute.adminMedia,
        builder: (context, state) => const MediaControlDashboard(),
      ),
      GoRoute(
        path: RoutePath.adminSettings,
        name: AppRoute.adminSettings,
        builder: (context, state) => const AdminSettingsPage(),
      ),
      GoRoute(
        path: RoutePath.studio,
        name: AppRoute.studio,
        builder: (context, state) => const StudioPage(),
      ),
      GoRoute(
        path: RoutePath.teacherHome,
        name: AppRoute.teacherHome,
        builder: (context, state) => const TeacherHomeScreen(),
      ),
      GoRoute(
        path: RoutePath.teacherEditor,
        name: AppRoute.teacherEditor,
        builder: (context, state) {
          final extra = state.extra;
          final courseId = extra is CourseEditorRouteArgs
              ? extra.courseId?.trim()
              : null;
          return CourseEditorScreen(courseId: courseId);
        },
      ),
      GoRoute(
        path: RoutePath.studioProfile,
        name: AppRoute.studioProfile,
        builder: (context, state) => const StudioProfilePage(),
      ),
      GoRoute(
        path: RoutePath.subscribe,
        name: AppRoute.subscribe,
        redirect: (context, state) => RoutePath.checkoutMembership,
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.booking,
        name: AppRoute.booking,
        builder: (context, state) => const BookingPage(),
      ),
      GoRoute(
        path: RoutePath.privacy,
        name: AppRoute.privacy,
        builder: (context, state) => const PrivacyPage(),
      ),
      GoRoute(
        path: RoutePath.terms,
        name: AppRoute.terms,
        builder: (context, state) => const TermsPage(),
      ),
      GoRoute(
        path: RoutePath.settings,
        name: AppRoute.settings,
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: RoutePath.community,
        name: AppRoute.community,
        builder: (context, state) {
          final extra = state.extra;
          final initialTab = extra is CommunityRouteArgs
              ? extra.initialTab
              : null;
          return CommunityPage(initialTab: initialTab);
        },
      ),
    ],
  );
});
