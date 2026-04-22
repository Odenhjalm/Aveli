import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/features/community/data/community_repository.dart';
import 'package:aveli/features/community/data/posts_repository.dart';
import 'package:aveli/features/community/data/admin_repository.dart';
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
  const TeacherDirectoryState({required this.teachers});

  final List<Map<String, dynamic>> teachers;
}

final teacherDirectoryProvider =
    AutoDisposeFutureProvider<TeacherDirectoryState>((ref) async {
      final repo = ref.watch(communityRepositoryProvider);
      try {
        final teachers = await repo.listTeachers();
        return TeacherDirectoryState(teachers: teachers);
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

class TeacherProfileState {
  const TeacherProfileState({
    required this.teacher,
    required this.services,
    required this.meditations,
    required this.profileMedia,
  });

  final Map<String, dynamic>? teacher;
  final List<Service> services;
  final List<Map<String, dynamic>> meditations;
  final TeacherProfileMediaPayload profileMedia;
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
        return TeacherProfileState(
          teacher: teacher,
          services: services,
          meditations: meditations,
          profileMedia: mediaPayload,
        );
      } catch (error, stackTrace) {
        throw AppFailure.from(error, stackTrace);
      }
    });

class AdminDashboardState {
  const AdminDashboardState({required this.isAdmin, required this.requests});

  final bool isAdmin;
  final List<Map<String, dynamic>> requests;
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

  static const empty = AdminMetricsState(
    totalUsers: 0,
    totalTeachers: 0,
    totalCourses: 0,
    publishedCourses: 0,
    paidOrdersTotal: 0,
    paidOrders30d: 0,
    payingCustomersTotal: 0,
    payingCustomers30d: 0,
    revenueTotalCents: 0,
    revenue30dCents: 0,
    loginEvents7d: 0,
    activeUsers7d: 0,
  );

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

  static const empty = AdminSettingsState(
    metrics: AdminMetricsState.empty,
    priorities: <TeacherPriorityEntry>[],
  );

  factory AdminSettingsState.fromJson(Map<String, dynamic> json) {
    final rawPriorities = json['priorities'] as List? ?? const <dynamic>[];
    return AdminSettingsState(
      metrics: AdminMetricsState.fromJson(
        json['metrics'] as Map<String, dynamic>?,
      ),
      priorities: rawPriorities
          .whereType<Map>()
          .map(
            (item) =>
                TeacherPriorityEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
    );
  }
}

final adminDashboardProvider = AutoDisposeFutureProvider<AdminDashboardState>((
  ref,
) async {
  return const AdminDashboardState(isAdmin: false, requests: []);
});

final adminSettingsProvider = AutoDisposeFutureProvider<AdminSettingsState>((
  ref,
) async {
  final repo = ref.watch(adminRepositoryProvider);
  try {
    final data = await repo.fetchSettings();
    return AdminSettingsState.fromJson(data);
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
