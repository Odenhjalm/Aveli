import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisdom/api/auth_repository.dart';
import 'package:wisdom/core/env/app_config.dart';
import 'package:wisdom/features/paywall/data/course_pricing_api.dart';

final coursePricingProvider = FutureProvider.family<CoursePricing, String>((
  ref,
  slug,
) async {
  final config = ref.watch(appConfigProvider);
  final tokens = ref.watch(tokenStorageProvider);
  final api = CoursePricingApi(
    tokenStorage: tokens,
    baseUrl: config.apiBaseUrl,
  );
  return api.fetch(slug);
});
