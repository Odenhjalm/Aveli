import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/features/community/data/community_repository.dart';
import 'package:aveli/features/community/data/posts_repository.dart';
import 'package:aveli/features/community/data/admin_repository.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/data/models/certificate.dart';
import 'package:aveli/features/community/data/meditations_repository.dart';
import 'package:aveli/data/models/service.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';
import 'package:aveli/data/models/community_post.dart';
import 'package:aveli/data/repositories/services_repository.dart';

final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return CommunityRepository(client);
});

final postsRepositoryProvider = Provider<PostsRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return PostsRepository(client: client);
});

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return AdminRepository(client);
});

final meditationsRepositoryProvider = Provider<MeditationsRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return MeditationsRepository(client);
});

final postsProvider = AutoDisposeFutureProvider<List<CommunityPost>>((
  ref,
) async {
  final repo = ref.watch(postsRepositoryProvider);
  return repo.feed(limit: 50);
});

class TeacherDirectoryState {
  const TeacherDirectoryState({
    required this.teachers,
    required this.certCount,
  });

  final List<Map<String, dynamic>> teachers;
  final Map<String, int> certCount;
}

final teacherDirectoryProvider =
    AutoDisposeFutureProvider<TeacherDirectoryState>((ref) async {
      final repo = ref.watch(communityRepositoryProvider);
      try {
        final teachers = await repo.listTeachers();
        final certCount = <String, int>{};
        for (final teacher in teachers) {
          final id = teacher['user_id'] as String?;
          if (id == null) continue;
          final count = teacher['verified_certificates'];
          certCount[id] = count is num ? count.toInt() : 0;
        }
        return TeacherDirectoryState(teachers: teachers, certCount: certCount);
      } catch (error, stackTrace) {
        throw AppFailure.from(error, stackTrace);
      }
    });

final communityServicesProvider = AutoDisposeFutureProvider<List<Service>>((
  ref,
) async {
  final repo = ref.watch(servicesRepositoryProvider);
  return repo.activeServices();
});

final myCertificatesProvider = AutoDisposeFutureProvider<List<Certificate>>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.profile == null) {
    return const <Certificate>[];
  }
  final repo = ref.watch(certificatesRepositoryProvider);
  try {
    final certs = await repo.myCertificates();
    return certs
        .where((c) => c.title != Certificate.teacherApplicationTitle)
        .toList(growable: false);
  } catch (error, stackTrace) {
    final failure = AppFailure.from(error, stackTrace);
    if (failure.kind == AppFailureKind.unauthorized) {
      return const <Certificate>[];
    }
    throw failure;
  }
});

class TeacherProfileState {
  const TeacherProfileState({
    required this.teacher,
    required this.services,
    required this.meditations,
    required this.certificates,
    required this.profileMedia,
  });

  final Map<String, dynamic>? teacher;
  final List<Service> services;
  final List<Map<String, dynamic>> meditations;
  final List<Certificate> certificates;
  final List<TeacherProfileMediaItem> profileMedia;
}

final teacherProfileProvider =
    AutoDisposeFutureProvider.family<TeacherProfileState, String>((
      ref,
      userId,
    ) async {
      final repo = ref.watch(communityRepositoryProvider);
      try {
        final detailFuture = repo.teacherDetail(userId);
        final mediaFuture = repo.teacherProfileMedia(userId);
        final detail = await detailFuture;
        final mediaPayload = await mediaFuture;
        final teacher = (detail['teacher'] as Map?)?.cast<String, dynamic>();
        final services = (detail['services'] as List? ?? [])
            .map(
              (item) =>
                  Service.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList(growable: false);
        final meditations = (detail['meditations'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        final certs = (detail['certificates'] as List? ?? [])
            .map((item) {
              final map = Map<String, dynamic>.from(item as Map);
              map.putIfAbsent('user_id', () => userId);
              return Certificate.fromJson(map);
            })
            .where((c) => c.title != Certificate.teacherApplicationTitle)
            .toList(growable: false);
        return TeacherProfileState(
          teacher: teacher,
          services: services,
          meditations: meditations,
          certificates: certs,
          profileMedia: mediaPayload.items,
        );
      } catch (error, stackTrace) {
        throw AppFailure.from(error, stackTrace);
      }
    });

class AdminDashboardState {
  const AdminDashboardState({
    required this.isAdmin,
    required this.requests,
    required this.certificates,
  });

  final bool isAdmin;
  final List<Map<String, dynamic>> requests;
  final List<Map<String, dynamic>> certificates;
}

class AdminMetricsState {
  const AdminMetricsState({
    required this.totalUsers,
    required this.totalTeachers,
    required this.totalCourses,
    required this.publishedCourses,
    required this.paidOrdersTotal,
    required this.paidOrders30d,
    required this.payingCustomersTotal,
    required this.payingCustomers30d,
    required this.revenueTotalCents,
    required this.revenue30dCents,
    required this.loginEvents7d,
    required this.activeUsers7d,
  });

  final int totalUsers;
  final int totalTeachers;
  final int totalCourses;
  final int publishedCourses;
  final int paidOrdersTotal;
  final int paidOrders30d;
  final int payingCustomersTotal;
  final int payingCustomers30d;
  final int revenueTotalCents;
  final int revenue30dCents;
  final int loginEvents7d;
  final int activeUsers7d;

  factory AdminMetricsState.fromJson(Map<String, dynamic>? json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
      return 0;
    }

    final data = json ?? const <String, dynamic>{};
    return AdminMetricsState(
      totalUsers: parseInt(data['total_users']),
      totalTeachers: parseInt(data['total_teachers']),
      totalCourses: parseInt(data['total_courses']),
      publishedCourses: parseInt(data['published_courses']),
      paidOrdersTotal: parseInt(data['paid_orders_total']),
      paidOrders30d: parseInt(data['paid_orders_30d']),
      payingCustomersTotal: parseInt(data['paying_customers_total']),
      payingCustomers30d: parseInt(data['paying_customers_30d']),
      revenueTotalCents: parseInt(data['revenue_total_cents']),
      revenue30dCents: parseInt(data['revenue_30d_cents']),
      loginEvents7d: parseInt(data['login_events_7d']),
      activeUsers7d: parseInt(data['active_users_7d']),
    );
  }
}

class TeacherPriorityEntry {
  const TeacherPriorityEntry({
    required this.teacherId,
    required this.displayName,
    required this.email,
    required this.photoUrl,
    required this.priority,
    required this.totalCourses,
    required this.publishedCourses,
    required this.notes,
    required this.updatedAt,
    required this.updatedBy,
    required this.updatedByName,
  });

  final String teacherId;
  final String? displayName;
  final String? email;
  final String? photoUrl;
  final int priority;
  final int totalCourses;
  final int publishedCourses;
  final String? notes;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String? updatedByName;

  factory TeacherPriorityEntry.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
      return 0;
    }

    DateTime? parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    return TeacherPriorityEntry(
      teacherId: json['teacher_id'] as String? ?? '',
      displayName: json['display_name'] as String?,
      email: json['email'] as String?,
      photoUrl: json['photo_url'] as String?,
      priority: parseInt(json['priority']),
      totalCourses: parseInt(json['total_courses']),
      publishedCourses: parseInt(json['published_courses']),
      notes: json['notes'] as String?,
      updatedAt: parseDate(json['updated_at']),
      updatedBy: json['updated_by'] as String?,
      updatedByName: json['updated_by_name'] as String?,
    );
  }
}

class AdminSettingsState {
  const AdminSettingsState({required this.metrics, required this.priorities});

  final AdminMetricsState metrics;
  final List<TeacherPriorityEntry> priorities;
}

final adminDashboardProvider = AutoDisposeFutureProvider<AdminDashboardState>((
  ref,
) async {
  try {
    final repo = ref.watch(adminRepositoryProvider);
    final data = await repo.fetchDashboard();
    final isAdmin = data['is_admin'] == true;
    if (!isAdmin) {
      return const AdminDashboardState(
        isAdmin: false,
        requests: [],
        certificates: [],
      );
    }
    final requests = (data['requests'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    final certs = (data['certificates'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    return AdminDashboardState(
      isAdmin: true,
      requests: requests,
      certificates: certs,
    );
  } catch (error, stackTrace) {
    throw AppFailure.from(error, stackTrace);
  }
});

final adminSettingsProvider = AutoDisposeFutureProvider<AdminSettingsState>((
  ref,
) async {
  try {
    final repo = ref.watch(adminRepositoryProvider);
    final data = await repo.fetchSettings();
    final metrics = AdminMetricsState.fromJson(
      data['metrics'] as Map<String, dynamic>?,
    );
    final list = (data['priorities'] as List? ?? const <dynamic>[])
        .map(
          (entry) =>
              TeacherPriorityEntry.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList(growable: false);
    return AdminSettingsState(metrics: metrics, priorities: list);
  } catch (error, stackTrace) {
    throw AppFailure.from(error, stackTrace);
  }
});

class ProfileViewState {
  const ProfileViewState({
    required this.profile,
    required this.isFollowing,
    required this.services,
    required this.meditations,
  });

  final Map<String, dynamic>? profile;
  final bool isFollowing;
  final List<Service> services;
  final List<Map<String, dynamic>> meditations;
}

final profileViewProvider =
    AutoDisposeFutureProvider.family<ProfileViewState, String>((
      ref,
      userId,
    ) async {
      try {
        final repo = ref.watch(communityRepositoryProvider);
        final detail = await repo.profileDetail(userId);
        final profile = detail['profile'] as Map<String, dynamic>?;
        final services =
            (detail['services'] as List?)
                ?.map(
                  (e) => Service.fromJson(Map<String, dynamic>.from(e as Map)),
                )
                .toList(growable: false) ??
            const <Service>[];
        final meditations =
            (detail['meditations'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList(growable: false) ??
            const <Map<String, dynamic>>[];
        final isFollowing = detail['is_following'] == true;
        return ProfileViewState(
          profile: profile,
          isFollowing: isFollowing,
          services: services,
          meditations: meditations,
        );
      } catch (error, stackTrace) {
        throw AppFailure.from(error, stackTrace);
      }
    });

class ServiceDetailState {
  const ServiceDetailState({required this.service, required this.provider});

  final Service? service;
  final Map<String, dynamic>? provider;
}

final serviceDetailProvider =
    AutoDisposeFutureProvider.family<ServiceDetailState, String>((
      ref,
      serviceId,
    ) async {
      try {
        final repo = ref.watch(communityRepositoryProvider);
        final detail = await repo.serviceDetail(serviceId);
        final rawService = detail['service'];
        final service = rawService is Map
            ? Service.fromJson(Map<String, dynamic>.from(rawService))
            : null;
        final provider = detail['provider'] is Map
            ? Map<String, dynamic>.from(detail['provider'] as Map)
            : null;
        return ServiceDetailState(service: service, provider: provider);
      } catch (error, stackTrace) {
        throw AppFailure.from(error, stackTrace);
      }
    });

final tarotRequestsProvider =
    AutoDisposeFutureProvider<List<Map<String, dynamic>>>((ref) async {
      try {
        final repo = ref.watch(communityRepositoryProvider);
        return await repo.tarotRequests();
      } catch (error, stackTrace) {
        throw AppFailure.from(error, stackTrace);
      }
    });

class PostPublisherController extends AutoDisposeAsyncNotifier<CommunityPost?> {
  @override
  FutureOr<CommunityPost?> build() => null;

  Future<void> publish({
    required String content,
    List<String>? mediaPaths,
  }) async {
    final repo = ref.read(postsRepositoryProvider);
    state = const AsyncLoading();
    try {
      final post = await repo.create(content: content, mediaPaths: mediaPaths);
      state = AsyncData(post);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
    }
  }
}

final postPublisherProvider =
    AutoDisposeAsyncNotifierProvider<PostPublisherController, CommunityPost?>(
      PostPublisherController.new,
    );
