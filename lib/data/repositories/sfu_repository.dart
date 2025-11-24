import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/api/auth_repository.dart';

class SfuToken {
  const SfuToken({required this.wsUrl, required this.token});

  factory SfuToken.fromJson(Map<String, dynamic> json) {
    return SfuToken(
      wsUrl: (json['ws_url'] ?? '') as String,
      token: (json['token'] ?? '') as String,
    );
  }

  final String wsUrl;
  final String token;
}

class SfuRepository {
  const SfuRepository(this._client);

  final ApiClient _client;

  Future<SfuToken> fetchToken(String seminarId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/sfu/token',
      body: {'seminar_id': seminarId},
    );
    return SfuToken.fromJson(response);
  }
}

final sfuRepositoryProvider = Provider<SfuRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return SfuRepository(client);
});
