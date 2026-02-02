import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:aveli/data/models/teacher_profile_media.dart';

import '../data/studio_repository.dart';

enum UploadJobStatus { pending, uploading, success, failed, cancelled }

class UploadJob {
  const UploadJob({
    required this.id,
    required this.courseId,
    required this.lessonId,
    required this.filename,
    this.displayName,
    required this.contentType,
    required this.isIntro,
    required this.data,
    required this.createdAt,
    this.status = UploadJobStatus.pending,
    this.progress = 0,
    this.attempts = 0,
    this.maxAttempts = 3,
    this.error,
    this.scheduledAt,
  });

  final String id;
  final String courseId;
  final String lessonId;
  final String filename;
  final String? displayName;
  final String contentType;
  final bool isIntro;
  final Uint8List data;
  final DateTime createdAt;
  final UploadJobStatus status;
  final double progress;
  final int attempts;
  final int maxAttempts;
  final String? error;
  final DateTime? scheduledAt;

  bool get hasData => data.isNotEmpty;

  UploadJob copyWith({
    UploadJobStatus? status,
    double? progress,
    int? attempts,
    int? maxAttempts,
    String? error,
    bool clearError = false,
    Uint8List? data,
    bool clearData = false,
    bool? isIntro,
    DateTime? scheduledAt,
  }) {
    return UploadJob(
      id: id,
      courseId: courseId,
      lessonId: lessonId,
      filename: filename,
      displayName: displayName,
      contentType: contentType,
      isIntro: isIntro ?? this.isIntro,
      data: clearData ? Uint8List(0) : (data ?? this.data),
      createdAt: createdAt,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      attempts: attempts ?? this.attempts,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      error: clearError ? null : (error ?? this.error),
      scheduledAt: scheduledAt,
    );
  }
}

class UploadQueueNotifier extends StateNotifier<List<UploadJob>> {
  UploadQueueNotifier(this._repo) : super(const []);

  final StudioRepository _repo;
  final Map<String, CancelToken> _activeTokens = {};
  Timer? _scheduledTimer;
  bool _isProcessing = false;
  bool _disposed = false;
  static const _uuid = Uuid();

  String enqueueUpload({
    required String courseId,
    required String lessonId,
    required Uint8List data,
    required String filename,
    String? displayName,
    required String contentType,
    required bool isIntro,
  }) {
    if (_disposed) {
      throw StateError('Upload queue is not available');
    }
    if (data.isEmpty) {
      throw StateError('Filinnehållet är tomt för $filename.');
    }
    if (kDebugMode) {
      debugPrint(
        'enqueueUpload: lesson=$lessonId filename=$filename bytes=${data.length} contentType=$contentType intro=$isIntro',
      );
    }
    final id = _uuid.v4();
    final job = UploadJob(
      id: id,
      courseId: courseId,
      lessonId: lessonId,
      filename: filename,
      displayName: displayName,
      contentType: contentType,
      isIntro: isIntro,
      data: data,
      createdAt: DateTime.now(),
    );
    state = [...state, job];
    _processQueue();
    _trimHistory();
    return id;
  }

  void cancelUpload(String id) {
    if (_disposed) return;
    final token = _activeTokens[id];
    if (token != null && !token.isCancelled) {
      token.cancel('cancelled-by-user');
      return;
    }
    _updateJob(
      id,
      (job) => job.copyWith(status: UploadJobStatus.cancelled, clearData: true),
    );
  }

  void retryUpload(String id) {
    if (_disposed) return;
    _updateJob(id, (job) {
      final resetJob = job.copyWith(
        status: UploadJobStatus.pending,
        progress: 0,
        attempts: 0,
        clearError: true,
        scheduledAt: null,
      );
      if (!resetJob.hasData) {
        throw StateError('Upload data not available for retry.');
      }
      return resetJob;
    });
    _processQueue();
  }

  void removeJob(String id) {
    if (_disposed) return;
    state = state.where((job) => job.id != id).toList(growable: false);
  }

  Future<void> _processQueue() async {
    if (_disposed || _isProcessing) return;
    final job = _nextReadyJob();
    if (job == null) return;
    _isProcessing = true;
    try {
      await _runJob(job);
    } finally {
      _isProcessing = false;
      if (!_disposed) {
        _processQueue();
      }
    }
  }

  UploadJob? _nextReadyJob() {
    final now = DateTime.now();
    UploadJob? candidate;
    Duration? earliestDelay;

    for (final job in state) {
      if (job.status != UploadJobStatus.pending) continue;
      if (job.scheduledAt == null || !job.scheduledAt!.isAfter(now)) {
        candidate = job;
        break;
      } else {
        final delay = job.scheduledAt!.difference(now);
        if (earliestDelay == null || delay < earliestDelay) {
          earliestDelay = delay;
        }
      }
    }

    if (candidate != null) {
      _scheduledTimer?.cancel();
      _scheduledTimer = null;
      return candidate;
    }

    if (earliestDelay != null) {
      _scheduledTimer?.cancel();
      _scheduledTimer = Timer(earliestDelay, () {
        _scheduledTimer = null;
        if (!_disposed) {
          _processQueue();
        }
      });
    }
    return null;
  }

  Future<void> _runJob(UploadJob job) async {
    final token = CancelToken();
    _activeTokens[job.id] = token;

    _updateJob(
      job.id,
      (current) => current.copyWith(
        status: UploadJobStatus.uploading,
        progress: 0,
        attempts: current.attempts + 1,
        clearError: true,
        scheduledAt: null,
      ),
    );

    try {
      final uploaded = await _repo.uploadLessonMedia(
        courseId: job.courseId,
        lessonId: job.lessonId,
        data: job.data,
        filename: job.filename,
        contentType: job.contentType,
        isIntro: job.isIntro,
        cancelToken: token,
        onProgress: (progress) {
          final fraction = progress.fraction.clamp(0.0, 1.0);
          _updateJob(job.id, (current) => current.copyWith(progress: fraction));
        },
      );

      final displayName = job.displayName?.trim();
      final lower = job.contentType.toLowerCase();
      final shouldCreateHomeControl =
          (lower.startsWith('audio/') || lower.startsWith('video/')) &&
          displayName != null &&
          displayName.isNotEmpty;

      if (shouldCreateHomeControl) {
        final mediaId = uploaded['id']?.toString().trim();
        if (mediaId != null && mediaId.isNotEmpty) {
          try {
            await _repo.createProfileMedia(
              mediaKind: TeacherProfileMediaKind.lessonMedia,
              mediaId: mediaId,
              title: displayName,
              isPublished: false,
            );
          } catch (error) {
            if (kDebugMode) {
              debugPrint(
                'Failed to create profile media item for upload: mediaId=$mediaId error=$error',
              );
            }
          }
        }
      }

      _updateJob(
        job.id,
        (current) => current.copyWith(
          status: UploadJobStatus.success,
          progress: 1,
          clearData: true,
          scheduledAt: null,
        ),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e) || token.isCancelled) {
        _updateJob(
          job.id,
          (current) => current.copyWith(
            status: UploadJobStatus.cancelled,
            clearData: true,
            error: 'Avbruten',
          ),
        );
      } else {
        final friendly = _friendlyErrorMessage(e);
        _handleFailure(job.id, friendly, statusCode: e.response?.statusCode);
      }
    } catch (e) {
      _handleFailure(job.id, e.toString());
    } finally {
      _activeTokens.remove(job.id);
    }
  }

  void _handleFailure(String jobId, String message, {int? statusCode}) {
    if (_disposed) return;
    final job = _jobById(jobId);
    if (job == null) return;

    if (kDebugMode) {
      debugPrint(
        'upload failure: job=$jobId status=$statusCode message=$message attempts=${job.attempts}',
      );
    }

    final normalizedMessage = switch (statusCode) {
      401 =>
        'Sessionen har gått ut. Logga in igen för att fortsätta ladda upp.',
      403 => 'Du har inte behörighet att ladda upp till den här lektionen.',
      422 =>
        'Uppladdningen kunde inte valideras. Kontrollera filen och försök igen.',
      _ => message,
    };

    if (statusCode == 401) {
      _updateJob(
        jobId,
        (current) => current.copyWith(
          status: UploadJobStatus.failed,
          error: normalizedMessage,
          clearData: true,
        ),
      );
      return;
    }
    if (statusCode == 403 || statusCode == 422) {
      _updateJob(
        jobId,
        (current) => current.copyWith(
          status: UploadJobStatus.failed,
          error: normalizedMessage,
        ),
      );
      return;
    }
    if (job.attempts >= job.maxAttempts) {
      _updateJob(
        jobId,
        (current) => current.copyWith(
          status: UploadJobStatus.failed,
          error: normalizedMessage,
        ),
      );
      return;
    }
    final computed = math.pow(2, job.attempts).toInt();
    final backoffSeconds = switch (computed) {
      < 1 => 1,
      > 30 => 30,
      _ => computed,
    };
    final scheduledAt = DateTime.now().add(Duration(seconds: backoffSeconds));
    _updateJob(
      jobId,
      (current) => current.copyWith(
        status: UploadJobStatus.pending,
        progress: 0,
        error: normalizedMessage,
        scheduledAt: scheduledAt,
      ),
    );
    Future.delayed(Duration(seconds: backoffSeconds), () {
      if (!_disposed) {
        _processQueue();
      }
    });
  }

  String _friendlyErrorMessage(DioException error) {
    final status = error.response?.statusCode;
    if (kDebugMode) {
      debugPrint(
        'upload error raw status=$status data=${error.response?.data}',
      );
    }
    if (status == 401) {
      return 'Sessionen har gått ut. Logga in igen för att fortsätta.';
    }
    if (status == 403) {
      return 'Du har inte behörighet att ladda upp till den här lektionen.';
    }
    if (status == 422) {
      return 'Uppladdningen kunde inte valideras. Kontrollera filen och försök igen.';
    }
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'] ?? data['message'] ?? data['error'];
      if (detail is String && detail.isNotEmpty) {
        return detail;
      }
    }
    final reason = error.response?.statusMessage;
    if (reason != null && reason.isNotEmpty) {
      return reason;
    }
    return error.message ?? 'Nätverksfel';
  }

  void _updateJob(String id, UploadJob Function(UploadJob) updater) {
    if (_disposed) return;
    final index = state.indexWhere((job) => job.id == id);
    if (index == -1) return;
    final updated = updater(state[index]);
    final newList = [...state];
    newList[index] = updated;
    state = newList;
  }

  void _trimHistory() {
    if (_disposed) return;
    final threshold = DateTime.now().subtract(const Duration(minutes: 10));
    state = state
        .where((job) {
          if (job.status == UploadJobStatus.success ||
              job.status == UploadJobStatus.cancelled) {
            return job.createdAt.isAfter(threshold);
          }
          return true;
        })
        .toList(growable: false);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final token in _activeTokens.values) {
      if (!token.isCancelled) {
        token.cancel('disposed');
      }
    }
    _activeTokens.clear();
    _scheduledTimer?.cancel();
    super.dispose();
  }

  UploadJob? _jobById(String id) {
    for (final job in state) {
      if (job.id == id) return job;
    }
    return null;
  }
}
