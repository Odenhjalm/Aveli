import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/home/data/home_entry_view_repository.dart';

final homeEntryViewRepositoryProvider = Provider<HomeEntryViewRepository>((
  ref,
) {
  final client = ref.watch(apiClientProvider);
  return HomeEntryViewRepository(client);
});

final homeEntryViewProvider =
    AutoDisposeFutureProvider<List<HomeEntryOngoingCourse>>((ref) async {
      try {
        final repository = ref.watch(homeEntryViewRepositoryProvider);
        final payload = await repository.fetchHomeEntryView();
        return payload.ongoingCourses;
      } catch (error, stackTrace) {
        throw AppFailure.from(error, stackTrace);
      }
    });
