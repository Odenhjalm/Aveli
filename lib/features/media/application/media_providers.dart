import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/api/auth_repository.dart';
import 'package:wisdom/core/env/app_config.dart';

import '../data/media_repository.dart';

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  final config = ref.watch(appConfigProvider);
  return MediaRepository(client: client, config: config);
});
