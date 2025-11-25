import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/api/auth_repository.dart';
import 'package:wisdom/data/models/service.dart';

class ServicesRepository {
  const ServicesRepository(this._client);

  final ApiClient _client;

  Future<List<Service>> activeServices() async {
    final response = await _client.get<Map<String, dynamic>>(
      '/services',
      queryParameters: {'status': 'active'},
    );
    final items = response['items'] as List? ?? const [];
    return items
        .map((item) => Service.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }
}

final servicesRepositoryProvider = Provider<ServicesRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return ServicesRepository(client);
});
