import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';

Object? _requireResponseField(Object? payload, String key, String label) {
  switch (payload) {
    case final Map data when data.containsKey(key):
      return data[key];
    case final Map _:
      throw StateError('$label saknar fältet "$key".');
    default:
      throw StateError('$label returnerade inte ett objekt.');
  }
}

String _requiredResponseString(Object? payload, String key, String label) {
  final value = _requireResponseField(payload, key, label);
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw StateError('$label fält "$key" måste vara en text.');
}

class ProfileAvatarRepository {
  ProfileAvatarRepository({
    required ApiClient client,
    required MediaPipelineRepository mediaPipeline,
  }) : _client = client,
       _mediaPipeline = mediaPipeline;

  final ApiClient _client;
  final MediaPipelineRepository _mediaPipeline;

  Future<MediaUploadTarget> initUpload({
    required String filename,
    required String mimeType,
    required int sizeBytes,
  }) async {
    final normalizedFilename = filename.trim();
    final normalizedMimeType = mimeType.trim().toLowerCase();
    if (normalizedFilename.isEmpty) {
      throw StateError('Bildfilen saknar filnamn.');
    }
    if (normalizedMimeType.isEmpty) {
      throw StateError('Bildfilen saknar filtyp.');
    }
    if (sizeBytes <= 0) {
      throw StateError('Bildfilen är tom.');
    }

    final response = await _client.raw.post<Object?>(
      ApiPaths.profileAvatarInit,
      data: <String, Object?>{
        'filename': normalizedFilename,
        'mime_type': normalizedMimeType,
        'size_bytes': sizeBytes,
      },
    );
    final target = MediaUploadTarget.fromCanonicalMediaAssetResponse(
      response.data,
    );
    final assetState = _requiredResponseString(
      response.data,
      'asset_state',
      'Profilbild init',
    );
    if (assetState != 'pending_upload') {
      throw StateError('Profilbild init returnerade ogiltigt asset_state.');
    }
    final expectedEndpoint = ApiPaths.mediaAssetUploadBytes(target.mediaId);
    if (target.uploadEndpoint != expectedEndpoint) {
      throw StateError('Profilbild init returnerade fel uppladdningsyta.');
    }
    return target;
  }

  Future<void> uploadBytes({
    required MediaUploadTarget target,
    required Uint8List bytes,
    required String contentType,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) {
    if (bytes.isEmpty) {
      throw StateError('Bildfilen är tom.');
    }
    return _mediaPipeline.uploadBytes(
      target: target,
      data: bytes,
      contentType: contentType,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  Future<MediaStatus> completeUpload({required String mediaAssetId}) {
    return _mediaPipeline.completeUpload(mediaId: mediaAssetId);
  }

  Future<MediaStatus> fetchStatus({required String mediaAssetId}) {
    return _mediaPipeline.fetchStatus(mediaAssetId);
  }

  Future<Profile> attachAvatar({required String mediaAssetId}) async {
    final data = await _client.post<Map<String, dynamic>>(
      ApiPaths.profileAvatarAttach,
      body: <String, Object?>{'media_asset_id': mediaAssetId},
    );
    return Profile.fromJson(data);
  }
}
