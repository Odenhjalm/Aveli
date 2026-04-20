import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/profile_avatar_repository.dart';

class ProfileAvatarUploadFile {
  const ProfileAvatarUploadFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;

  int get sizeBytes => bytes.length;
}

typedef ProfileAvatarPicker = Future<ProfileAvatarUploadFile?> Function();

final profileAvatarPickerProvider = Provider<ProfileAvatarPicker>(
  (_) => pickProfileAvatarFile,
);

enum ProfileAvatarUploadStage {
  empty,
  picked,
  initializing,
  uploading,
  completing,
  waitingForReady,
  attaching,
  attached,
  failed,
}

extension ProfileAvatarUploadStageState on ProfileAvatarUploadStage {
  bool get isBusy {
    return switch (this) {
      ProfileAvatarUploadStage.picked ||
      ProfileAvatarUploadStage.initializing ||
      ProfileAvatarUploadStage.uploading ||
      ProfileAvatarUploadStage.completing ||
      ProfileAvatarUploadStage.waitingForReady ||
      ProfileAvatarUploadStage.attaching => true,
      _ => false,
    };
  }
}

class ProfileAvatarUploadSnapshot {
  const ProfileAvatarUploadSnapshot({
    required this.stage,
    this.previewBytes,
    this.progress = 0,
    this.status,
    this.errorMessage,
    this.attachedAvatarMediaId,
  });

  const ProfileAvatarUploadSnapshot.empty()
    : stage = ProfileAvatarUploadStage.empty,
      previewBytes = null,
      progress = 0,
      status = null,
      errorMessage = null,
      attachedAvatarMediaId = null;

  final ProfileAvatarUploadStage stage;
  final Uint8List? previewBytes;
  final double progress;
  final String? status;
  final String? errorMessage;
  final String? attachedAvatarMediaId;

  bool get isBusy => stage.isBusy;

  ProfileAvatarUploadSnapshot copyWith({
    ProfileAvatarUploadStage? stage,
    Uint8List? previewBytes,
    bool clearPreviewBytes = false,
    double? progress,
    String? status,
    bool clearStatus = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? attachedAvatarMediaId,
    bool clearAttachedAvatarMediaId = false,
  }) {
    return ProfileAvatarUploadSnapshot(
      stage: stage ?? this.stage,
      previewBytes: clearPreviewBytes
          ? null
          : previewBytes ?? this.previewBytes,
      progress: progress ?? this.progress,
      status: clearStatus ? null : status ?? this.status,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      attachedAvatarMediaId: clearAttachedAvatarMediaId
          ? null
          : attachedAvatarMediaId ?? this.attachedAvatarMediaId,
    );
  }

  ProfileAvatarUploadSnapshot asFailed() {
    return copyWith(
      stage: ProfileAvatarUploadStage.failed,
      progress: 0,
      status: 'Profilbilden kunde inte sparas.',
      errorMessage: 'Försök igen eller välj en annan bild.',
    );
  }
}

typedef ProfileAvatarUploadSnapshotChanged =
    void Function(ProfileAvatarUploadSnapshot snapshot);

final profileAvatarUploadControllerProvider =
    Provider<ProfileAvatarUploadController>((ref) {
      final repository = ref.watch(profileAvatarRepositoryProvider);
      return ProfileAvatarUploadController(repository: repository);
    });

class ProfileAvatarUploadController {
  const ProfileAvatarUploadController({
    required ProfileAvatarRepository repository,
  }) : _repository = repository;

  final ProfileAvatarRepository _repository;

  Future<Profile> uploadAndAttach(
    ProfileAvatarUploadFile picked, {
    required ProfileAvatarUploadSnapshotChanged onSnapshot,
  }) async {
    final mimeType = picked.mimeType.trim().toLowerCase();
    if (!supportedProfileAvatarMimeTypes.contains(mimeType)) {
      throw StateError('Endast JPG, PNG eller WebP stöds.');
    }
    if (picked.bytes.isEmpty) {
      throw StateError('Bildfilen är tom.');
    }

    onSnapshot(
      ProfileAvatarUploadSnapshot(
        stage: ProfileAvatarUploadStage.picked,
        previewBytes: picked.bytes,
        status: 'Bild vald. Förbereder uppladdning...',
      ),
    );

    onSnapshot(
      ProfileAvatarUploadSnapshot(
        stage: ProfileAvatarUploadStage.initializing,
        previewBytes: picked.bytes,
        status: 'Begär uppladdning...',
      ),
    );
    final target = await _repository.initUpload(
      filename: picked.name,
      mimeType: mimeType,
      sizeBytes: picked.sizeBytes,
    );

    onSnapshot(
      ProfileAvatarUploadSnapshot(
        stage: ProfileAvatarUploadStage.uploading,
        previewBytes: picked.bytes,
        status: 'Laddar upp profilbild...',
      ),
    );
    await _repository.uploadBytes(
      target: target,
      bytes: picked.bytes,
      contentType: mimeType,
      onSendProgress: (sent, total) {
        final resolvedTotal = total > 0 ? total : picked.sizeBytes;
        final progress = resolvedTotal <= 0 ? 0.0 : sent / resolvedTotal;
        onSnapshot(
          ProfileAvatarUploadSnapshot(
            stage: ProfileAvatarUploadStage.uploading,
            previewBytes: picked.bytes,
            progress: progress.clamp(0.0, 1.0),
            status: 'Laddar upp profilbild...',
          ),
        );
      },
    );

    onSnapshot(
      ProfileAvatarUploadSnapshot(
        stage: ProfileAvatarUploadStage.completing,
        previewBytes: picked.bytes,
        progress: 1,
        status: 'Verifierar uppladdningen...',
      ),
    );
    final completed = await _repository.completeUpload(
      mediaAssetId: target.mediaId,
    );
    if (completed.mediaId != target.mediaId || completed.state != 'uploaded') {
      throw StateError('Profilbildens uppladdning kunde inte verifieras.');
    }

    onSnapshot(
      ProfileAvatarUploadSnapshot(
        stage: ProfileAvatarUploadStage.waitingForReady,
        previewBytes: picked.bytes,
        progress: 1,
        status: 'Bearbetar bilden...',
      ),
    );
    await _waitForAvatarReady(target.mediaId);

    onSnapshot(
      ProfileAvatarUploadSnapshot(
        stage: ProfileAvatarUploadStage.attaching,
        previewBytes: picked.bytes,
        progress: 1,
        status: 'Sparar profilbilden...',
      ),
    );
    final profile = await _repository.attachAvatar(
      mediaAssetId: target.mediaId,
    );

    onSnapshot(
      ProfileAvatarUploadSnapshot(
        stage: ProfileAvatarUploadStage.attached,
        previewBytes: picked.bytes,
        progress: 1,
        status: 'Profilbilden är sparad.',
        attachedAvatarMediaId: profile.avatarMediaId ?? target.mediaId,
      ),
    );
    return profile;
  }

  Future<void> _waitForAvatarReady(String mediaAssetId) async {
    for (
      var attempt = 0;
      attempt < profileAvatarReadyPollAttempts;
      attempt += 1
    ) {
      final status = await _repository.fetchStatus(mediaAssetId: mediaAssetId);
      if (status.mediaId != mediaAssetId) {
        throw StateError('Statussvaret gäller fel mediafil.');
      }
      switch (status.state) {
        case 'ready':
          return;
        case 'failed':
          throw StateError('Profilbilden kunde inte bearbetas.');
        default:
          if (attempt < profileAvatarReadyPollAttempts - 1) {
            await Future<void>.delayed(profileAvatarReadyPollInterval);
          }
      }
    }
    throw StateError(
      'Profilbilden bearbetas fortfarande. Försök igen om en stund.',
    );
  }
}

const profileAvatarReadyPollAttempts = 12;
const profileAvatarReadyPollInterval = Duration(seconds: 1);
const supportedProfileAvatarMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
};

Future<ProfileAvatarUploadFile?> pickProfileAvatarFile() async {
  final typeGroup = fs.XTypeGroup(
    label: 'profilbild',
    extensions: const ['jpg', 'jpeg', 'png', 'webp'],
  );
  final file = await fs.openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return null;
  final mimeType = profileAvatarMimeTypeFromFilename(file.name);
  if (mimeType == null) {
    throw StateError('Endast JPG, PNG eller WebP stöds.');
  }
  final bytes = await file.readAsBytes();
  return ProfileAvatarUploadFile(
    name: file.name,
    mimeType: mimeType,
    bytes: bytes,
  );
}

String? profileAvatarMimeTypeFromFilename(String filename) {
  final lower = filename.trim().toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  return null;
}

String profileAvatarActionText(ProfileAvatarUploadStage stage) {
  return switch (stage) {
    ProfileAvatarUploadStage.empty => 'Lägg till profilbild',
    ProfileAvatarUploadStage.picked => 'Bild vald',
    ProfileAvatarUploadStage.initializing => 'Förbereder uppladdning',
    ProfileAvatarUploadStage.uploading => 'Laddar upp profilbild',
    ProfileAvatarUploadStage.completing => 'Verifierar bilden',
    ProfileAvatarUploadStage.waitingForReady => 'Bearbetar bilden',
    ProfileAvatarUploadStage.attaching => 'Sparar profilbild',
    ProfileAvatarUploadStage.attached => 'Profilbilden är sparad',
    ProfileAvatarUploadStage.failed => 'Försök igen',
  };
}

String profileAvatarDefaultStatusText(ProfileAvatarUploadStage stage) {
  return switch (stage) {
    ProfileAvatarUploadStage.empty =>
      'Tryck på cirkeln för att välja en bild från din enhet.',
    ProfileAvatarUploadStage.attached =>
      'Tryck igen om du vill byta profilbild.',
    ProfileAvatarUploadStage.failed =>
      'Profilbild är valfritt. Du kan fortsätta utan bild.',
    _ => 'Vänta medan bilden sparas.',
  };
}

String profileAvatarVisibleStatus(ProfileAvatarUploadSnapshot snapshot) {
  final status = snapshot.status;
  if (status != null && status.isNotEmpty) {
    return status;
  }
  return profileAvatarDefaultStatusText(snapshot.stage);
}
