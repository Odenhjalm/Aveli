import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/profile_avatar_repository.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/app_avatar.dart';

class OnboardingAvatarFile {
  const OnboardingAvatarFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;

  int get sizeBytes => bytes.length;
}

typedef OnboardingAvatarPicker = Future<OnboardingAvatarFile?> Function();

final onboardingAvatarPickerProvider = Provider<OnboardingAvatarPicker>(
  (_) => _pickOnboardingAvatarFile,
);

enum _AvatarUploadStage {
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

const _avatarReadyPollAttempts = 12;
const _avatarReadyPollInterval = Duration(seconds: 1);
const _supportedAvatarMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};

Future<OnboardingAvatarFile?> _pickOnboardingAvatarFile() async {
  final typeGroup = fs.XTypeGroup(
    label: 'profilbild',
    extensions: const ['jpg', 'jpeg', 'png', 'webp'],
  );
  final file = await fs.openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return null;
  final mimeType = _avatarMimeTypeFromFilename(file.name);
  if (mimeType == null) {
    throw StateError('Endast JPG, PNG eller WebP stöds.');
  }
  final bytes = await file.readAsBytes();
  return OnboardingAvatarFile(
    name: file.name,
    mimeType: mimeType,
    bytes: bytes,
  );
}

String? _avatarMimeTypeFromFilename(String filename) {
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

class OnboardingProfilePage extends ConsumerStatefulWidget {
  const OnboardingProfilePage({super.key, this.referralCode});

  final String? referralCode;

  @override
  ConsumerState<OnboardingProfilePage> createState() =>
      _OnboardingProfilePageState();
}

class _OnboardingProfilePageState extends ConsumerState<OnboardingProfilePage> {
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _bioCtrl;
  bool _isSubmitting = false;
  bool _isHydratingControllers = false;
  String? _hydratedProfileId;
  String? _nameError;
  _AvatarUploadStage _avatarStage = _AvatarUploadStage.empty;
  Uint8List? _avatarPreviewBytes;
  double _avatarProgress = 0;
  String? _avatarStatus;
  String? _avatarError;
  String? _attachedAvatarMediaId;

  bool get _isNameValid => _displayNameCtrl.text.trim().isNotEmpty;
  bool get _isAvatarBusy {
    return switch (_avatarStage) {
      _AvatarUploadStage.picked ||
      _AvatarUploadStage.initializing ||
      _AvatarUploadStage.uploading ||
      _AvatarUploadStage.completing ||
      _AvatarUploadStage.waitingForReady ||
      _AvatarUploadStage.attaching => true,
      _ => false,
    };
  }

  @override
  void initState() {
    super.initState();
    _displayNameCtrl = TextEditingController();
    _displayNameCtrl.addListener(_handleDisplayNameChanged);
    _bioCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _displayNameCtrl.removeListener(_handleDisplayNameChanged);
    _displayNameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _handleDisplayNameChanged() {
    if (_isHydratingControllers || !mounted) return;
    setState(() {
      if (_nameError != null) {
        _nameError = null;
      }
    });
  }

  void _hydrateControllers(Profile? profile) {
    if (profile == null || _hydratedProfileId == profile.id) return;
    _hydratedProfileId = profile.id;
    _isHydratingControllers = true;
    try {
      _displayNameCtrl.text = profile.displayName ?? '';
      _bioCtrl.text = profile.bio ?? '';
    } finally {
      _isHydratingControllers = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).profile;
    _hydrateControllers(profile);

    return AppScaffold(
      title: 'Skapa profil',
      showHomeAction: false,
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: p16,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Vad ska vi kalla dig?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  gap12,
                  Text(
                    'Skriv ditt namn så kan vi välkomna dig rätt. Bio är valfritt och profilbild kan läggas till nu eller senare.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (widget.referralCode?.trim().isNotEmpty == true) ...[
                    gap12,
                    Text(
                      'Din referenskod kopplas när profilen sparas.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  gap24,
                  _buildAvatarPicker(context, profile),
                  gap24,
                  TextField(
                    controller: _displayNameCtrl,
                    enabled: !_isSubmitting,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Namn',
                      hintText: 'Ditt namn',
                      errorText: _nameError,
                    ),
                  ),
                  gap16,
                  TextField(
                    controller: _bioCtrl,
                    enabled: !_isSubmitting,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Bio',
                      hintText: 'Valfritt',
                    ),
                  ),
                  gap20,
                  FilledButton(
                    onPressed: (!_isNameValid || _isSubmitting)
                        ? null
                        : _saveProfile,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Fortsätt till välkomststeget'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPicker(BuildContext context, Profile? profile) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final photoUrl = profile?.photoUrl?.trim();
    final hasSavedAvatar =
        _attachedAvatarMediaId?.trim().isNotEmpty == true ||
        profile?.avatarMediaId?.trim().isNotEmpty == true;
    final effectiveStage =
        _avatarStage == _AvatarUploadStage.empty && hasSavedAvatar
        ? _AvatarUploadStage.attached
        : _avatarStage;
    final canPickAvatar = !_isAvatarBusy && !_isSubmitting;
    final progress = _avatarProgress <= 0 || _avatarProgress >= 1
        ? null
        : _avatarProgress;

    Widget image;
    if (_avatarPreviewBytes != null && _avatarPreviewBytes!.isNotEmpty) {
      image = Image.memory(
        _avatarPreviewBytes!,
        fit: BoxFit.cover,
        width: 112,
        height: 112,
        gaplessPlayback: true,
      );
    } else if (photoUrl != null && photoUrl.isNotEmpty) {
      image = AppAvatar(url: photoUrl, size: 112);
    } else {
      image = Icon(
        Icons.person_add_alt_1,
        size: 42,
        color: colorScheme.onSurfaceVariant,
      );
    }

    return Column(
      children: [
        Semantics(
          button: true,
          label: 'Välj profilbild',
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: canPickAvatar ? _pickAndUploadAvatar : null,
              child: SizedBox(
                width: 124,
                height: 124,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _avatarStage == _AvatarUploadStage.failed
                              ? colorScheme.error
                              : colorScheme.outlineVariant,
                          width: 2,
                        ),
                      ),
                      child: ClipOval(child: Center(child: image)),
                    ),
                    if (_avatarStage == _AvatarUploadStage.uploading)
                      SizedBox(
                        width: 122,
                        height: 122,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 4,
                        ),
                      ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: _AvatarBadge(stage: effectiveStage),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _avatarActionText(effectiveStage),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _avatarStatusText(effectiveStage),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (_avatarError != null && _avatarError!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _avatarError!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  String _avatarActionText(_AvatarUploadStage stage) {
    return switch (stage) {
      _AvatarUploadStage.empty => 'Lägg till profilbild',
      _AvatarUploadStage.picked => 'Bild vald',
      _AvatarUploadStage.initializing => 'Förbereder uppladdning',
      _AvatarUploadStage.uploading => 'Laddar upp profilbild',
      _AvatarUploadStage.completing => 'Verifierar bilden',
      _AvatarUploadStage.waitingForReady => 'Bearbetar bilden',
      _AvatarUploadStage.attaching => 'Sparar profilbild',
      _AvatarUploadStage.attached => 'Profilbilden är sparad',
      _AvatarUploadStage.failed => 'Försök igen',
    };
  }

  String _avatarStatusText(_AvatarUploadStage stage) {
    if (_avatarStatus != null && _avatarStatus!.isNotEmpty) {
      return _avatarStatus!;
    }
    return switch (stage) {
      _AvatarUploadStage.empty =>
        'Tryck på cirkeln för att välja en bild från din enhet.',
      _AvatarUploadStage.attached => 'Tryck igen om du vill byta profilbild.',
      _AvatarUploadStage.failed =>
        'Profilbild är valfritt. Du kan fortsätta utan bild.',
      _ => 'Vänta medan bilden sparas.',
    };
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_isAvatarBusy) return;
    try {
      final picker = ref.read(onboardingAvatarPickerProvider);
      final picked = await picker();
      if (!mounted || picked == null) return;
      final mimeType = picked.mimeType.trim().toLowerCase();
      if (!_supportedAvatarMimeTypes.contains(mimeType)) {
        throw StateError('Endast JPG, PNG eller WebP stöds.');
      }
      if (picked.bytes.isEmpty) {
        throw StateError('Bildfilen är tom.');
      }

      setState(() {
        _avatarStage = _AvatarUploadStage.picked;
        _avatarPreviewBytes = picked.bytes;
        _avatarProgress = 0;
        _avatarStatus = 'Bild vald. Förbereder uppladdning...';
        _avatarError = null;
      });

      final repo = ref.read(profileAvatarRepositoryProvider);
      await _uploadAndAttachAvatar(repo, picked, mimeType);
    } catch (error, stackTrace) {
      _handleAvatarFailure(error, stackTrace);
    }
  }

  Future<void> _uploadAndAttachAvatar(
    ProfileAvatarRepository repo,
    OnboardingAvatarFile picked,
    String mimeType,
  ) async {
    if (!mounted) return;
    setState(() {
      _avatarStage = _AvatarUploadStage.initializing;
      _avatarStatus = 'Begär uppladdning...';
      _avatarProgress = 0;
    });

    final target = await repo.initUpload(
      filename: picked.name,
      mimeType: mimeType,
      sizeBytes: picked.sizeBytes,
    );
    if (!mounted) return;
    setState(() {
      _avatarStage = _AvatarUploadStage.uploading;
      _avatarStatus = 'Laddar upp profilbild...';
    });

    await repo.uploadBytes(
      target: target,
      bytes: picked.bytes,
      contentType: mimeType,
      onSendProgress: (sent, total) {
        if (!mounted) return;
        final resolvedTotal = total > 0 ? total : picked.sizeBytes;
        final progress = resolvedTotal <= 0 ? 0.0 : sent / resolvedTotal;
        setState(() => _avatarProgress = progress.clamp(0.0, 1.0));
      },
    );
    if (!mounted) return;
    setState(() {
      _avatarStage = _AvatarUploadStage.completing;
      _avatarStatus = 'Verifierar uppladdningen...';
      _avatarProgress = 1;
    });

    final completed = await repo.completeUpload(mediaAssetId: target.mediaId);
    if (completed.mediaId != target.mediaId || completed.state != 'uploaded') {
      throw StateError('Profilbildens uppladdning kunde inte verifieras.');
    }
    if (!mounted) return;
    setState(() {
      _avatarStage = _AvatarUploadStage.waitingForReady;
      _avatarStatus = 'Bearbetar bilden...';
    });

    await _waitForAvatarReady(repo, target.mediaId);
    if (!mounted) return;
    setState(() {
      _avatarStage = _AvatarUploadStage.attaching;
      _avatarStatus = 'Sparar profilbilden...';
    });

    final profile = await repo.attachAvatar(mediaAssetId: target.mediaId);
    if (!mounted) return;
    setState(() {
      _avatarStage = _AvatarUploadStage.attached;
      _attachedAvatarMediaId = profile.avatarMediaId ?? target.mediaId;
      _avatarStatus = 'Profilbilden är sparad.';
      _avatarError = null;
      _avatarProgress = 1;
    });
  }

  Future<void> _waitForAvatarReady(
    ProfileAvatarRepository repo,
    String mediaAssetId,
  ) async {
    for (var attempt = 0; attempt < _avatarReadyPollAttempts; attempt += 1) {
      final status = await repo.fetchStatus(mediaAssetId: mediaAssetId);
      if (status.mediaId != mediaAssetId) {
        throw StateError('Statussvaret gäller fel mediafil.');
      }
      switch (status.state) {
        case 'ready':
          return;
        case 'failed':
          throw StateError(
            status.errorMessage?.isNotEmpty == true
                ? status.errorMessage!
                : 'Profilbilden kunde inte bearbetas.',
          );
        default:
          if (attempt < _avatarReadyPollAttempts - 1) {
            await Future<void>.delayed(_avatarReadyPollInterval);
          }
      }
    }
    throw StateError(
      'Profilbilden bearbetas fortfarande. Försök igen om en stund.',
    );
  }

  void _handleAvatarFailure(Object error, StackTrace stackTrace) {
    if (!mounted) return;
    final failure = AppFailure.from(error, stackTrace);
    setState(() {
      _avatarStage = _AvatarUploadStage.failed;
      _avatarStatus = 'Profilbilden kunde inte sparas.';
      _avatarError = failure.message;
      _avatarProgress = 0;
    });
    showSnack(context, 'Kunde inte spara profilbilden: ${failure.message}');
  }

  Future<void> _saveProfile() async {
    final displayName = _displayNameCtrl.text.trim();
    if (displayName.isEmpty) {
      setState(() => _nameError = 'Skriv ditt namn för att fortsätta.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _nameError = null;
    });

    try {
      final bio = _bioCtrl.text.trim();
      await ref
          .read(authControllerProvider.notifier)
          .createProfile(
            displayName: displayName,
            bio: bio,
            referralCode: widget.referralCode,
          );
      if (!mounted || !context.mounted) return;
      context.goNamed(AppRoute.welcome);
    } catch (error, stackTrace) {
      if (!mounted) return;
      final failure = AppFailure.from(error, stackTrace);
      showSnack(context, 'Kunde inte spara profilen: ${failure.message}');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({required this.stage});

  final _AvatarUploadStage stage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isError = stage == _AvatarUploadStage.failed;
    final isDone = stage == _AvatarUploadStage.attached;
    final isBusy = switch (stage) {
      _AvatarUploadStage.picked ||
      _AvatarUploadStage.initializing ||
      _AvatarUploadStage.uploading ||
      _AvatarUploadStage.completing ||
      _AvatarUploadStage.waitingForReady ||
      _AvatarUploadStage.attaching => true,
      _ => false,
    };

    final icon = isError
        ? Icons.priority_high
        : isDone
        ? Icons.check
        : isBusy
        ? Icons.cloud_upload_outlined
        : Icons.add_a_photo_outlined;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isError ? colorScheme.error : colorScheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.surface, width: 3),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: 18,
        color: isError ? colorScheme.onError : colorScheme.onPrimary,
      ),
    );
  }
}
