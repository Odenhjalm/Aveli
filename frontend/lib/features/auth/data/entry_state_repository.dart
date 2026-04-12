import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/domain/models/entry_state.dart';

class EntryStateRepository {
  const EntryStateRepository(this._client);

  final ApiClient _client;

  Future<EntryState> fetchEntryState() async {
    final data = await _client.get<Map<String, dynamic>>(ApiPaths.entryState);
    return EntryState.fromJson(data);
  }
}

final entryStateRepositoryProvider = Provider<EntryStateRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return EntryStateRepository(client);
});
