import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/data/models/activity.dart';
import 'package:wisdom/data/models/service.dart';
import 'package:wisdom/data/repositories/feed_repository.dart';
import 'package:wisdom/data/repositories/services_repository.dart';

final homeFeedProvider = AutoDisposeFutureProvider<List<Activity>>((ref) async {
  final repo = ref.watch(feedRepositoryProvider);
  return repo.fetchFeed(limit: 20);
});

final homeServicesProvider = AutoDisposeFutureProvider<List<Service>>((
  ref,
) async {
  final repo = ref.watch(servicesRepositoryProvider);
  return repo.activeServices();
});
