import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/data/models/seminar.dart';
import 'package:aveli/data/repositories/seminar_repository.dart';

final hostSeminarsProvider = FutureProvider.autoDispose<List<Seminar>>((
  ref,
) async {
  final repository = ref.watch(seminarRepositoryProvider);
  return repository.listHostSeminars();
});

final seminarDetailProvider = FutureProvider.autoDispose
    .family<SeminarDetail, String>((ref, id) async {
      final repository = ref.watch(seminarRepositoryProvider);
      return repository.getSeminarDetail(id);
    });

final publicSeminarsProvider = FutureProvider.autoDispose<List<Seminar>>((
  ref,
) async {
  final repository = ref.watch(seminarRepositoryProvider);
  return repository.listPublicSeminars();
});

final publicSeminarDetailProvider = FutureProvider.autoDispose
    .family<SeminarDetail, String>((ref, id) async {
      final repository = ref.watch(seminarRepositoryProvider);
      return repository.getPublicSeminar(id);
    });
