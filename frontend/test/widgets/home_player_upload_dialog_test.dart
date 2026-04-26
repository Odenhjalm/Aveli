import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/widgets/home_player_upload_dialog.dart';
import 'package:aveli/features/studio/widgets/wav_upload_source.dart';
import 'package:aveli/features/studio/widgets/wav_upload_types.dart';

const _homePlayerChunkSizeBytes = 8 * 1024 * 1024;
const _largeHomePlayerWavBytes = _homePlayerChunkSizeBytes * 2 + 17;

typedef _UploadPayloadBuilder =
    Map<String, Object?> Function({
      required String filename,
      required String mimeType,
      required int sizeBytes,
    });

class _FakeApiClient extends Fake implements ApiClient {}

class _DialogStudioRepository extends StudioRepository {
  _DialogStudioRepository({
    List<String>? events,
    _UploadPayloadBuilder? uploadPayloadBuilder,
  }) : events = events ?? <String>[],
       _uploadPayloadBuilder = uploadPayloadBuilder ?? _chunkUploadPayload,
       super(client: _FakeApiClient());

  final List<String> events;
  final _UploadPayloadBuilder _uploadPayloadBuilder;
  int requestUploadUrlCalls = 0;
  int uploadCreateCalls = 0;
  int refreshCalls = 0;
  int createFromStorageCalls = 0;
  String? lastRequestedFilename;
  String? lastRequestedMimeType;

  @override
  Future<Map<String, Object?>> requestHomePlayerUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
  }) async {
    requestUploadUrlCalls += 1;
    events.add('POST /api/home-player/media-assets/upload-url');
    lastRequestedFilename = filename;
    lastRequestedMimeType = mimeType;
    return _uploadPayloadBuilder(
      filename: filename,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
    );
  }

  @override
  Future<HomePlayerUploadItem> uploadHomePlayerUpload({
    required String title,
    required String mediaAssetId,
    bool active = true,
  }) async {
    uploadCreateCalls += 1;
    events.add('studio.uploadHomePlayerUpload');
    return HomePlayerUploadItem(
      id: 'upload-1',
      mediaAssetId: mediaAssetId,
      title: title,
      kind: 'audio',
      active: active,
      createdAt: DateTime.utc(2026, 4, 21, 10, 0),
      mediaState: 'uploaded',
    );
  }

  @override
  Future<Map<String, Object?>> refreshHomePlayerUploadUrl({
    required String objectPath,
    required String mimeType,
  }) {
    refreshCalls += 1;
    return super.refreshHomePlayerUploadUrl(
      objectPath: objectPath,
      mimeType: mimeType,
    );
  }

  @override
  Future<HomePlayerUploadItem> createHomePlayerUploadFromStorage({
    required String title,
    required String storagePath,
    required String contentType,
    required int byteSize,
    required String originalName,
    bool active = true,
    String storageBucket = 'course-media',
  }) {
    createFromStorageCalls += 1;
    return super.createHomePlayerUploadFromStorage(
      title: title,
      storagePath: storagePath,
      contentType: contentType,
      byteSize: byteSize,
      originalName: originalName,
      active: active,
      storageBucket: storageBucket,
    );
  }
}

Map<String, Object?> _legacyUploadBytesPayload({
  required String filename,
  required String mimeType,
  required int sizeBytes,
}) {
  return <String, Object?>{
    'media_asset_id': 'media-1',
    'asset_state': 'pending_upload',
    'upload_session_id': 'upload-session-1',
    'upload_endpoint': '/api/media-assets/media-1/upload-bytes',
    'expires_at': '2026-04-21T12:00:00Z',
  };
}

Map<String, Object?> _chunkUploadPayload({
  required String filename,
  required String mimeType,
  required int sizeBytes,
}) {
  return <String, Object?>{
    'media_asset_id': 'media-1',
    'asset_state': 'pending_upload',
    'upload_session_id': 'upload-session-1',
    'upload_endpoint':
        '/api/media-assets/media-1/upload-sessions/upload-session-1/chunks',
    'session_status_endpoint':
        '/api/media-assets/media-1/upload-sessions/upload-session-1/status',
    'finalize_endpoint':
        '/api/media-assets/media-1/upload-sessions/upload-session-1/finalize',
    'chunk_size': _homePlayerChunkSizeBytes,
    'expected_chunks': _expectedChunkCount(sizeBytes),
    'expires_at': '2026-04-21T12:00:00Z',
  };
}

int _expectedChunkCount(int sizeBytes) {
  return (sizeBytes + _homePlayerChunkSizeBytes - 1) ~/
      _homePlayerChunkSizeBytes;
}

void main() {
  testWidgets('WAV upload refuses the legacy upload-bytes target', (
    tester,
  ) async {
    final events = <String>[];
    final studioRepo = _DialogStudioRepository(
      events: events,
      uploadPayloadBuilder: _legacyUploadBytesPayload,
    );
    final harness = await _PipelineHarness.create(events: events);
    final pipelineRepo = MediaPipelineRepository(client: harness.client);
    final streamingUploads = <_RecordedStreamingUpload>[];
    final file = _UnreadableWavUploadFile();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studioRepositoryProvider.overrideWithValue(studioRepo),
          mediaPipelineRepositoryProvider.overrideWithValue(pipelineRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return FilledButton(
                  onPressed: () {
                    showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => HomePlayerUploadDialog(
                        file: file,
                        title: 'Morgonljud',
                        contentType: 'audio/wav',
                        textBundle: _textBundle(),
                        uploadFileOverride: _recordingUpload(
                          streamingUploads,
                          events: events,
                        ),
                      ),
                    );
                  },
                  child: const Text('Ã–ppna dialog'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ã–ppna dialog'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(file.readAsBytesCalls, 0);
    expect(
      streamingUploads.map((upload) => upload.uploadEndpoint.path),
      isNot(contains('/api/media-assets/media-1/upload-bytes')),
      reason: 'Home Player WAV uploads must not use the old full-file route.',
    );
    expect(
      harness.adapter.requestsFor(
        '/api/media-assets/media-1/upload-completion',
      ),
      isEmpty,
    );
    expect(studioRepo.uploadCreateCalls, 0);
  });

  testWidgets(
    'WAV upload uses chunk session transport before creating the Home Player row',
    (tester) async {
      final events = <String>[];
      final studioRepo = _DialogStudioRepository(events: events);
      final harness = await _PipelineHarness.create(events: events);
      final pipelineRepo = MediaPipelineRepository(client: harness.client);
      final streamingUploads = <_RecordedStreamingUpload>[];
      final file = _UnreadableWavUploadFile();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studioRepositoryProvider.overrideWithValue(studioRepo),
            mediaPipelineRepositoryProvider.overrideWithValue(pipelineRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return FilledButton(
                    onPressed: () {
                      showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => HomePlayerUploadDialog(
                          file: file,
                          title: 'Morgonljud',
                          contentType: 'audio/wav',
                          textBundle: _textBundle(),
                          uploadFileOverride: _recordingUpload(
                            streamingUploads,
                            events: events,
                          ),
                        ),
                      );
                    },
                    child: const Text('Öppna dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Öppna dialog'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(studioRepo.requestUploadUrlCalls, 1);
      expect(studioRepo.uploadCreateCalls, 1);
      expect(studioRepo.refreshCalls, 0);
      expect(studioRepo.createFromStorageCalls, 0);
      expect(find.text('Laddar upp ljud'), findsNothing);
      expect(studioRepo.lastRequestedMimeType, 'audio/wav');
      expect(file.readAsBytesCalls, 0);

      expect(streamingUploads, isNotEmpty);
      for (final streamingUpload in streamingUploads) {
        expect(streamingUpload.contentType, 'audio/wav');
        expect(
          streamingUpload.headers['X-Aveli-Upload-Session'],
          'upload-session-1',
        );
        expect(
          streamingUpload.headers['Authorization'],
          'Bearer ${_jwtWithExpSeconds(4102444800)}',
        );
      }
      final expectedChunkPaths = List<String>.generate(
        _expectedChunkCount(file.size),
        (index) =>
            '/api/media-assets/media-1/upload-sessions/upload-session-1/chunks/$index',
      );
      expect(
        streamingUploads.map((upload) => upload.uploadEndpoint.path).toList(),
        expectedChunkPaths,
      );
      expect(streamingUploads.map((upload) => upload.bodySize), <int>[
        _homePlayerChunkSizeBytes,
        _homePlayerChunkSizeBytes,
        17,
      ]);
      expect(streamingUploads.map((upload) => upload.headers['Content-Range']), <
        String
      >[
        'bytes 0-${_homePlayerChunkSizeBytes - 1}/$_largeHomePlayerWavBytes',
        'bytes $_homePlayerChunkSizeBytes-${_homePlayerChunkSizeBytes * 2 - 1}/$_largeHomePlayerWavBytes',
        'bytes ${_homePlayerChunkSizeBytes * 2}-${_largeHomePlayerWavBytes - 1}/$_largeHomePlayerWavBytes',
      ]);
      expect(
        streamingUploads.map(
          (upload) => upload.headers['X-Aveli-Chunk-Sha256'],
        ),
        everyElement(matches(RegExp(r'^[a-f0-9]{64}$'))),
      );
      expect(
        harness.adapter.requestsFor('/api/media-assets/media-1/upload-bytes'),
        isEmpty,
      );

      expect(
        events,
        containsAllInOrder(<String>[
          'POST /api/home-player/media-assets/upload-url',
          'PUT /api/media-assets/media-1/upload-sessions/upload-session-1/chunks/0',
          'PUT /api/media-assets/media-1/upload-sessions/upload-session-1/chunks/1',
          'PUT /api/media-assets/media-1/upload-sessions/upload-session-1/chunks/2',
          'POST /api/media-assets/media-1/upload-sessions/upload-session-1/finalize',
          'studio.uploadHomePlayerUpload',
        ]),
      );
      expect(
        harness.adapter.requestsFor('/api/media-assets/media-1/upload-session'),
        isEmpty,
      );

      final finalizeRequests = harness.adapter.requestsFor(
        '/api/media-assets/media-1/upload-sessions/upload-session-1/finalize',
      );
      expect(finalizeRequests, hasLength(1));
      expect(finalizeRequests.single.method, 'POST');
      expect(
        harness.adapter.requestsFor(
          '/api/media-assets/media-1/upload-completion',
        ),
        isEmpty,
      );

      final statusRequests = harness.adapter.requestsFor(
        '/api/media-assets/media-1/status',
      );
      expect(statusRequests, hasLength(1));
      expect(statusRequests.single.method, 'GET');
    },
  );

  testWidgets('upload dialog accepts M4A through canonical upload-url flow', (
    tester,
  ) async {
    final studioRepo = _DialogStudioRepository();
    final harness = await _PipelineHarness.create();
    final pipelineRepo = MediaPipelineRepository(client: harness.client);
    final streamingUploads = <_RecordedStreamingUpload>[];
    final file = WavUploadFile(
      fs.XFile.fromData(
        Uint8List.fromList(<int>[1, 2, 3, 4]),
        name: 'demo.m4a',
        mimeType: 'audio/mp4',
      ),
      'audio/mp4',
      4,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studioRepositoryProvider.overrideWithValue(studioRepo),
          mediaPipelineRepositoryProvider.overrideWithValue(pipelineRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return FilledButton(
                  onPressed: () {
                    showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => HomePlayerUploadDialog(
                        file: file,
                        title: 'Kvällsljud',
                        contentType: 'audio/mp4',
                        textBundle: _textBundle(),
                        uploadFileOverride: _recordingUpload(streamingUploads),
                      ),
                    );
                  },
                  child: const Text('Öppna dialog'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Öppna dialog'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(studioRepo.requestUploadUrlCalls, 1);
    expect(studioRepo.lastRequestedMimeType, 'audio/m4a');
    expect(studioRepo.createFromStorageCalls, 0);
    expect(streamingUploads.single.contentType, 'audio/m4a');
  });

  testWidgets('upload dialog stops polling after auth failure', (tester) async {
    final studioRepo = _DialogStudioRepository();
    final harness = await _PipelineHarness.create(
      handler: (options) {
        if (options.path ==
                '/api/media-assets/media-1/upload-sessions/upload-session-1/finalize' &&
            options.method.toUpperCase() == 'POST') {
          return _jsonResponse(
            statusCode: 200,
            body: <String, Object?>{
              'upload_session_id': 'upload-session-1',
              'media_asset_id': 'media-1',
              'asset_state': 'uploaded',
            },
          );
        }
        if (options.path == '/api/media-assets/media-1/status' &&
            options.method.toUpperCase() == 'GET') {
          return _jsonResponse(
            statusCode: 403,
            body: <String, Object?>{'detail': 'forbidden'},
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      },
    );
    final pipelineRepo = MediaPipelineRepository(client: harness.client);
    final streamingUploads = <_RecordedStreamingUpload>[];
    final file = WavUploadFile(
      fs.XFile.fromData(
        Uint8List.fromList(<int>[1, 2, 3, 4]),
        name: 'demo.mp3',
        mimeType: 'audio/mpeg',
      ),
      'audio/mpeg',
      4,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studioRepositoryProvider.overrideWithValue(studioRepo),
          mediaPipelineRepositoryProvider.overrideWithValue(pipelineRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return FilledButton(
                  onPressed: () {
                    showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => HomePlayerUploadDialog(
                        file: file,
                        title: 'Morgonljud',
                        contentType: 'audio/mpeg',
                        textBundle: _textBundle(),
                        uploadFileOverride: _recordingUpload(streamingUploads),
                      ),
                    );
                  },
                  child: const Text('Öppna dialog'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Öppna dialog'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      harness.adapter.requestsFor('/api/media-assets/media-1/status'),
      hasLength(1),
    );

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(
      harness.adapter.requestsFor('/api/media-assets/media-1/status'),
      hasLength(1),
    );
    expect(
      find.text(_textBundle().requireValue('home.player_upload.retry_action')),
      findsOneWidget,
    );
  });

  testWidgets(
    'upload dialog stops periodic polling after transient refresh failure',
    (tester) async {
      final studioRepo = _DialogStudioRepository();
      final harness = await _PipelineHarness.create(
        handler: (options) {
          if (options.path ==
                  '/api/media-assets/media-1/upload-sessions/upload-session-1/finalize' &&
              options.method.toUpperCase() == 'POST') {
            return _jsonResponse(
              statusCode: 200,
              body: <String, Object?>{
                'upload_session_id': 'upload-session-1',
                'media_asset_id': 'media-1',
                'asset_state': 'uploaded',
              },
            );
          }
          if (options.path == '/api/media-assets/media-1/status' &&
              options.method.toUpperCase() == 'GET') {
            return _jsonResponse(
              statusCode: 500,
              body: <String, Object?>{'detail': 'temporary'},
            );
          }
          return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
        },
      );
      final pipelineRepo = MediaPipelineRepository(client: harness.client);
      final streamingUploads = <_RecordedStreamingUpload>[];
      final file = WavUploadFile(
        fs.XFile.fromData(
          Uint8List.fromList(<int>[1, 2, 3, 4]),
          name: 'demo.mp3',
          mimeType: 'audio/mpeg',
        ),
        'audio/mpeg',
        4,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studioRepositoryProvider.overrideWithValue(studioRepo),
            mediaPipelineRepositoryProvider.overrideWithValue(pipelineRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return FilledButton(
                    onPressed: () {
                      showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => HomePlayerUploadDialog(
                          file: file,
                          title: 'Morgonljud',
                          contentType: 'audio/mpeg',
                          textBundle: _textBundle(),
                          uploadFileOverride: _recordingUpload(
                            streamingUploads,
                          ),
                        ),
                      );
                    },
                    child: const Text('Öppna dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Öppna dialog'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        harness.adapter.requestsFor('/api/media-assets/media-1/status'),
        hasLength(1),
      );

      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(
        harness.adapter.requestsFor('/api/media-assets/media-1/status'),
        hasLength(1),
      );
      expect(
        find.text(
          _textBundle().requireValue('home.player_upload.retry_action'),
        ),
        findsOneWidget,
      );
    },
  );
}

HomePlayerTextBundle _textBundle() {
  const sourceContract =
      'actual_truth/contracts/backend_text_catalog_contract.md';
  const apiSurface = '/studio/home-player/library';
  HomePlayerCatalogTextValue entry(
    String textId,
    String authorityClass,
    String value,
  ) {
    return HomePlayerCatalogTextValue(
      surfaceId: 'TXT-SURF-075',
      textId: textId,
      authorityClass: authorityClass,
      canonicalOwner: 'backend_text_catalog',
      sourceContract: sourceContract,
      backendNamespace: 'backend_text_catalog.home',
      apiSurface: apiSurface,
      deliverySurface: apiSurface,
      renderSurface:
          'frontend/lib/features/studio/widgets/home_player_upload_dialog.dart',
      language: 'sv',
      value: value,
    );
  }

  return HomePlayerTextBundle(
    entries: <String, HomePlayerCatalogTextValue>{
      'home.player_upload.title': entry(
        'home.player_upload.title',
        'contract_text',
        'Lägg till ljud i hemspelaren',
      ),
      'home.player_upload.prepare_status': entry(
        'home.player_upload.prepare_status',
        'backend_status_text',
        'Förbereder uppladdning...',
      ),
      'home.player_upload.uploading_status': entry(
        'home.player_upload.uploading_status',
        'backend_status_text',
        'Laddar upp ljud...',
      ),
      'home.player_upload.registering_status': entry(
        'home.player_upload.registering_status',
        'backend_status_text',
        'Registrerar ljudfil...',
      ),
      'home.player_upload.processing_status': entry(
        'home.player_upload.processing_status',
        'backend_status_text',
        'Ljudet bearbetas...',
      ),
      'home.player_upload.ready_status': entry(
        'home.player_upload.ready_status',
        'backend_status_text',
        'Ljudet är redo.',
      ),
      'home.player_upload.failed_error': entry(
        'home.player_upload.failed_error',
        'backend_error_text',
        'Ljudet kunde inte laddas upp.',
      ),
      'home.player_upload.wait_until_complete_status': entry(
        'home.player_upload.wait_until_complete_status',
        'backend_status_text',
        'Vänta tills uppladdningen är klar eller avbryt.',
      ),
      'home.player_upload.close_action': entry(
        'home.player_upload.close_action',
        'contract_text',
        'Stäng',
      ),
      'home.player_upload.cancel_action': entry(
        'home.player_upload.cancel_action',
        'contract_text',
        'Avbryt',
      ),
      'home.player_upload.retry_action': entry(
        'home.player_upload.retry_action',
        'contract_text',
        'Försök igen',
      ),
      'home.player_upload.cancelled_status': entry(
        'home.player_upload.cancelled_status',
        'backend_status_text',
        'Uppladdningen avbröts.',
      ),
      'home.player_upload.audio_only_error': entry(
        'home.player_upload.audio_only_error',
        'backend_error_text',
        'Home-spelaren stöder bara ljudfiler.',
      ),
      'home.player_upload.start_failed_error': entry(
        'home.player_upload.start_failed_error',
        'backend_error_text',
        'Kunde inte starta uppladdningen. Försök igen.',
      ),
      'home.player_upload.save_failed_error': entry(
        'home.player_upload.save_failed_error',
        'backend_error_text',
        'Kunde inte spara uppladdningen. Försök igen.',
      ),
      'home.player_upload.processing_failed_error': entry(
        'home.player_upload.processing_failed_error',
        'backend_error_text',
        'Bearbetningen misslyckades.',
      ),
      'home.player_upload.refresh_failed_error': entry(
        'home.player_upload.refresh_failed_error',
        'backend_error_text',
        'Kunde inte uppdatera statusen just nu.',
      ),
      'home.player_upload.unsupported_audio_error': entry(
        'home.player_upload.unsupported_audio_error',
        'backend_error_text',
        'Endast WAV eller MP3 stöds för ljud i Home-spelaren.',
      ),
      'home.player_upload.unsupported_video_error': entry(
        'home.player_upload.unsupported_video_error',
        'backend_error_text',
        'Home-spelaren stöder bara ljud. Välj en WAV- eller MP3-fil.',
      ),
      'home.player_upload.unsupported_other_error': entry(
        'home.player_upload.unsupported_other_error',
        'backend_error_text',
        'Välj en WAV- eller MP3-fil.',
      ),
    },
  );
}

class _UnreadableWavUploadFile extends WavUploadFile {
  _UnreadableWavUploadFile({int size = _largeHomePlayerWavBytes})
    : super(
        fs.XFile.fromData(
          Uint8List(0),
          name: 'large-home-player.wav',
          mimeType: 'audio/wav',
        ),
        'audio/wav',
        size,
      );

  int readAsBytesCalls = 0;

  @override
  Future<Uint8List> readAsBytes() {
    readAsBytesCalls += 1;
    throw StateError('Home Player uploads must use streaming transport');
  }

  @override
  Future<Uint8List> readRangeBytes(int start, int endExclusive) async {
    if (start < 0 || endExclusive < start || endExclusive > size) {
      throw RangeError.range(start, 0, size, 'start');
    }
    return Uint8List(endExclusive - start);
  }
}

class _RecordedStreamingUpload {
  const _RecordedStreamingUpload({
    required this.uploadEndpoint,
    required this.file,
    required this.contentType,
    required this.headers,
    required this.bodySize,
    required this.byteStart,
    required this.byteEndExclusive,
  });

  final Uri uploadEndpoint;
  final WavUploadFile file;
  final String contentType;
  final Map<String, String> headers;
  final int bodySize;
  final int? byteStart;
  final int? byteEndExclusive;
}

HomePlayerStreamingUpload _recordingUpload(
  List<_RecordedStreamingUpload> calls, {
  List<String>? events,
}) {
  return ({
    required Uri uploadEndpoint,
    required WavUploadFile file,
    required String contentType,
    required Map<String, String> headers,
    required void Function(int sent, int total) onProgress,
    WavUploadCancelToken? cancelToken,
    int? byteStart,
    int? byteEndExclusive,
    Uint8List? bodyBytes,
  }) async {
    if (cancelToken?.isCancelled == true) {
      throw const WavUploadFailure(WavUploadFailureKind.cancelled);
    }
    events?.add('PUT ${uploadEndpoint.path}');
    calls.add(
      _RecordedStreamingUpload(
        uploadEndpoint: uploadEndpoint,
        file: file,
        contentType: contentType,
        headers: Map<String, String>.from(headers),
        bodySize: bodyBytes?.length ?? file.size,
        byteStart: byteStart,
        byteEndExclusive: byteEndExclusive,
      ),
    );
    final total = bodyBytes?.length ?? file.size;
    onProgress(total, total);
  };
}

class _PipelineHarness {
  _PipelineHarness({required this.client, required this.adapter});

  final ApiClient client;
  final _RecordingAdapter adapter;

  static Future<_PipelineHarness> create({
    ResponseBody Function(RequestOptions options)? handler,
    List<String>? events,
  }) async {
    final storage = _MemoryFlutterSecureStorage();
    final tokens = TokenStorage(storage: storage);
    await tokens.saveTokens(
      accessToken: _jwtWithExpSeconds(4102444800),
      refreshToken: 'rt-1',
    );

    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:1',
      tokenStorage: tokens,
    );
    final adapter = _RecordingAdapter(handler ?? _defaultHandler, events);
    client.raw.httpClientAdapter = adapter;
    return _PipelineHarness(client: client, adapter: adapter);
  }

  static ResponseBody _defaultHandler(RequestOptions options) {
    if (options.path == '/api/media-assets/media-1/upload-session' &&
        options.method.toUpperCase() == 'POST') {
      return _jsonResponse(
        statusCode: 201,
        body: _chunkUploadPayload(
          filename: 'large-home-player.wav',
          mimeType: 'audio/wav',
          sizeBytes: _largeHomePlayerWavBytes,
        ),
      );
    }
    if (options.path.startsWith(
          '/api/media-assets/media-1/upload-sessions/upload-session-1/chunks/',
        ) &&
        options.method.toUpperCase() == 'PUT') {
      final chunkIndex = int.parse(options.path.split('/').last);
      final byteStart = chunkIndex * _homePlayerChunkSizeBytes;
      final maxChunkEnd = byteStart + _homePlayerChunkSizeBytes - 1;
      final byteEnd = maxChunkEnd < _largeHomePlayerWavBytes
          ? maxChunkEnd
          : _largeHomePlayerWavBytes - 1;
      return _jsonResponse(
        statusCode: 200,
        body: <String, Object?>{
          'upload_session_id': 'upload-session-1',
          'media_asset_id': 'media-1',
          'chunk_index': chunkIndex,
          'byte_start': byteStart,
          'byte_end': byteEnd,
          'size_bytes': byteEnd - byteStart + 1,
          'sha256': 'a' * 64,
          'received_bytes': byteEnd + 1,
        },
      );
    }
    if (options.path ==
            '/api/media-assets/media-1/upload-sessions/upload-session-1/status' &&
        options.method.toUpperCase() == 'GET') {
      return _jsonResponse(
        statusCode: 200,
        body: <String, Object?>{
          'upload_session_id': 'upload-session-1',
          'media_asset_id': 'media-1',
          'owner_user_id': 'teacher-1',
          'state': 'open',
          'asset_state': 'pending_upload',
          'total_bytes': _largeHomePlayerWavBytes,
          'content_type': 'audio/wav',
          'chunk_size': _homePlayerChunkSizeBytes,
          'expected_chunks': _expectedChunkCount(_largeHomePlayerWavBytes),
          'received_bytes': _largeHomePlayerWavBytes,
          'expires_at': '2026-04-21T12:00:00Z',
          'chunks': const <Object?>[],
        },
      );
    }
    if (options.path ==
            '/api/media-assets/media-1/upload-sessions/upload-session-1/finalize' &&
        options.method.toUpperCase() == 'POST') {
      return _jsonResponse(
        statusCode: 200,
        body: <String, Object?>{
          'upload_session_id': 'upload-session-1',
          'media_asset_id': 'media-1',
          'asset_state': 'uploaded',
        },
      );
    }
    if (options.path == '/api/media-assets/media-1/upload-bytes' &&
        options.method.toUpperCase() == 'PUT') {
      return _jsonResponse(statusCode: 200, body: const <String, Object?>{});
    }
    if (options.path == '/api/media-assets/media-1/upload-completion' &&
        options.method.toUpperCase() == 'POST') {
      return _jsonResponse(
        statusCode: 200,
        body: <String, Object?>{
          'media_asset_id': 'media-1',
          'asset_state': 'uploaded',
        },
      );
    }
    if (options.path == '/api/media-assets/media-1/status' &&
        options.method.toUpperCase() == 'GET') {
      return _jsonResponse(
        statusCode: 200,
        body: <String, Object?>{
          'media_asset_id': 'media-1',
          'asset_state': 'ready',
        },
      );
    }
    return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
  }
}

ResponseBody _jsonResponse({
  required int statusCode,
  required Map<String, Object?> body,
}) {
  return ResponseBody.fromString(
    json.encode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

String _jwtWithExpSeconds(int expSeconds) {
  final header = base64Url.encode(utf8.encode(json.encode({'alg': 'HS256'})));
  final payload = base64Url.encode(
    utf8.encode(json.encode({'exp': expSeconds})),
  );
  return '$header.$payload.signature';
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._handler, this._events);

  final ResponseBody Function(RequestOptions options) _handler;
  final List<String>? _events;
  final List<_RecordedRequest> _requests = <_RecordedRequest>[];

  List<_RecordedRequest> requestsFor(String path) => _requests
      .where((request) => request.path == path)
      .toList(growable: false);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _events?.add('${options.method.toUpperCase()} ${options.path}');
    _requests.add(
      _RecordedRequest(
        path: options.path,
        method: options.method.toUpperCase(),
        data: options.data,
      ),
    );
    return _handler(options);
  }
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.path,
    required this.method,
    required this.data,
  });

  final String path;
  final String method;
  final Object? data;
}

class _MemoryFlutterSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    _values.clear();
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    return Map<String, String>.from(_values);
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    return _values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }
}
