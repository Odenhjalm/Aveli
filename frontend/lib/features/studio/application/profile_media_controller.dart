import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';

import 'studio_providers.dart';

class TeacherProfileMediaState extends Equatable {
  const TeacherProfileMediaState({
    required this.items,
    required this.lessonSources,
    required this.recordingSources,
  });

  factory TeacherProfileMediaState.fromPayload(
    TeacherProfileMediaPayload payload,
  ) {
    return TeacherProfileMediaState(
      items: _sortedItems(payload.items),
      lessonSources: payload.lessonMedia,
      recordingSources: payload.seminarRecordings,
    );
  }

  static const empty = TeacherProfileMediaState(
    items: [],
    lessonSources: [],
    recordingSources: [],
  );

  final List<TeacherProfileMediaItem> items;
  final List<TeacherProfileLessonSource> lessonSources;
  final List<TeacherProfileRecordingSource> recordingSources;

  List<TeacherProfileMediaItem> get sortedItems => _sortedItems(items);

  TeacherProfileMediaState copyWith({
    List<TeacherProfileMediaItem>? items,
    List<TeacherProfileLessonSource>? lessonSources,
    List<TeacherProfileRecordingSource>? recordingSources,
  }) {
    return TeacherProfileMediaState(
      items: items != null ? _sortedItems(items) : this.items,
      lessonSources: lessonSources ?? this.lessonSources,
      recordingSources: recordingSources ?? this.recordingSources,
    );
  }

  static List<TeacherProfileMediaItem> _sortedItems(
    List<TeacherProfileMediaItem> items,
  ) {
    final copy = List<TeacherProfileMediaItem>.from(items);
    copy.sort((a, b) {
      final diff = a.position.compareTo(b.position);
      if (diff != 0) return diff;
      return a.createdAt.compareTo(b.createdAt);
    });
    return copy;
  }

  @override
  List<Object?> get props => [items, lessonSources, recordingSources];
}

class TeacherProfileMediaController
    extends AutoDisposeAsyncNotifier<TeacherProfileMediaState> {
  StudioRepository get _repository => ref.read(studioRepositoryProvider);

  @override
  FutureOr<TeacherProfileMediaState> build() async {
    return _load();
  }

  Future<TeacherProfileMediaState> _load() async {
    try {
      final payload = await _repository.fetchProfileMedia();
      return TeacherProfileMediaState.fromPayload(payload);
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

  Future<void> createItem({
    required TeacherProfileMediaKind kind,
    String? mediaId,
    String? externalUrl,
    String? title,
    String? description,
    bool? isPublished,
    Map<String, dynamic>? metadata,
    String? coverMediaId,
    String? coverImageUrl,
  }) async {
    state = const AsyncLoading();
    try {
      await _repository.createProfileMedia(
        mediaKind: kind,
        mediaId: mediaId,
        externalUrl: externalUrl,
        title: title,
        description: description,
        isPublished: isPublished,
        metadata: metadata,
        coverMediaId: coverMediaId,
        coverImageUrl: coverImageUrl,
      );
      final snapshot = await _load();
      state = AsyncData(snapshot);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
      rethrow;
    }
  }

  Future<void> updateItem(
    String itemId, {
    String? title,
    String? description,
    bool? isPublished,
    int? position,
    Map<String, dynamic>? metadata,
    String? coverMediaId,
    String? coverImageUrl,
  }) async {
    state = const AsyncLoading();
    try {
      await _repository.updateProfileMedia(
        itemId,
        title: title,
        description: description,
        isPublished: isPublished,
        position: position,
        metadata: metadata,
        coverMediaId: coverMediaId,
        coverImageUrl: coverImageUrl,
      );
      final snapshot = await _load();
      state = AsyncData(snapshot);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
      rethrow;
    }
  }

  Future<void> deleteItem(String itemId) async {
    state = const AsyncLoading();
    try {
      await _repository.deleteProfileMedia(itemId);
      final snapshot = await _load();
      state = AsyncData(snapshot);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
      rethrow;
    }
  }

  Future<void> togglePublish(String itemId, bool publish) async {
    await updateItem(itemId, isPublished: publish);
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final ordered = current.sortedItems.toList();
    if (oldIndex < 0 || oldIndex >= ordered.length) return;
    if (newIndex > ordered.length) newIndex = ordered.length;
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);

    state = const AsyncLoading();
    try {
      for (var index = 0; index < ordered.length; index++) {
        final item = ordered[index];
        await _repository.updateProfileMedia(item.id, position: index);
      }
      final snapshot = await _load();
      state = AsyncData(snapshot);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
      rethrow;
    }
  }
}

final teacherProfileMediaProvider =
    AutoDisposeAsyncNotifierProvider<
      TeacherProfileMediaController,
      TeacherProfileMediaState
    >(TeacherProfileMediaController.new);
