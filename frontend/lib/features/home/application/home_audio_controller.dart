import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/features/home/data/home_audio_repository.dart';

final homeAudioRepositoryProvider = Provider<HomeAudioRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return HomeAudioRepository(client);
});

class HomeAudioState extends Equatable {
  const HomeAudioState({required this.items, required this.textBundle});

  factory HomeAudioState.fromPayload(HomeAudioFeedPayload payload) {
    return HomeAudioState(
      items: List<HomeAudioFeedItem>.unmodifiable(payload.items),
      textBundle: payload.textBundle,
    );
  }

  static const empty = HomeAudioState(
    items: [],
    textBundle: HomePlayerTextBundle(),
  );

  final List<HomeAudioFeedItem> items;
  final HomePlayerTextBundle textBundle;

  @override
  List<Object?> get props => [items, textBundle];
}

class HomeAudioController extends AutoDisposeAsyncNotifier<HomeAudioState> {
  HomeAudioRepository get _repository => ref.read(homeAudioRepositoryProvider);

  @override
  FutureOr<HomeAudioState> build() async {
    return _load();
  }

  Future<HomeAudioState> _load() async {
    try {
      final payload = await _repository.fetchHomeAudio();
      return HomeAudioState.fromPayload(payload);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final snapshot = await _load();
      state = AsyncData(snapshot);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
    }
  }
}

final homeAudioProvider =
    AutoDisposeAsyncNotifierProvider<HomeAudioController, HomeAudioState>(
      HomeAudioController.new,
    );
