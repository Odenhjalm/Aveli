import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/utils/snack.dart';

import 'cover_upload_source.dart';

class CoverUploadCard extends ConsumerStatefulWidget {
  const CoverUploadCard({
    super.key,
    required this.courseId,
    this.onCoverQueued,
    this.onUploadError,
    this.pickFileOverride,
    this.uploadFileOverride,
  });

  final String? courseId;
  final void Function(String courseId, String mediaId)? onCoverQueued;
  final void Function(String courseId, String message)? onUploadError;
  final Future<CoverUploadFile?> Function()? pickFileOverride;
  final Future<void> Function({
    required Uri uploadUrl,
    required Map<String, String> headers,
    required CoverUploadFile file,
    required void Function(int sent, int total) onProgress,
  })?
  uploadFileOverride;

  @override
  ConsumerState<CoverUploadCard> createState() => _CoverUploadCardState();
}

class _CoverUploadCardState extends ConsumerState<CoverUploadCard> {
  static const Set<String> _allowedMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  CoverUploadFile? _selectedFile;
  double _progress = 0.0;
  String? _status;
  String? _error;
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final courseId = widget.courseId;
    if (courseId == null || courseId.isEmpty) {
      showSnack(
        context,
        'Spara kursen först för att kunna ladda upp kursbild.',
      );
      return;
    }

    final picker = widget.pickFileOverride ?? pickCoverFile;
    final picked = await picker();
    if (!mounted) return;
    if (picked == null) {
      setState(() => _status = 'Ingen fil vald.');
      return;
    }

    final resolvedMime = _resolveMimeType(picked);
    if (resolvedMime == null || !_allowedMimeTypes.contains(resolvedMime)) {
      final message = 'Endast JPG, PNG eller WebP tillats.';
      if (!mounted) return;
      setState(() {
        _selectedFile = picked;
        _uploading = false;
        _error = message;
        _status = 'Ogiltig bildtyp.';
      });
      showSnack(context, message);
      widget.onUploadError?.call(courseId, message);
      return;
    }

    setState(() {
      _selectedFile = picked;
      _progress = 0.0;
      _status = 'Begarar uppladdningslank...';
      _error = null;
      _uploading = true;
    });

    try {
      final repo = ref.read(mediaPipelineRepositoryProvider);
      final upload = await repo.requestCoverUploadUrl(
        filename: picked.name,
        mimeType: resolvedMime,
        sizeBytes: picked.size,
        courseId: courseId,
      );

      if (!mounted) return;
      setState(() => _status = 'Laddar upp kursbild...');

      final uploader = widget.uploadFileOverride ?? uploadCoverFile;
      await uploader(
        uploadUrl: upload.uploadUrl,
        headers: upload.headers,
        file: picked,
        onProgress: (sent, total) {
          if (!mounted) return;
          final fraction = total <= 0 ? 0.0 : sent / total;
          setState(() => _progress = fraction.clamp(0.0, 1.0));
        },
      );

      if (!mounted) return;
      setState(() {
        _uploading = false;
        _status = 'Uppladdad. Bearbetas...';
      });
      widget.onCoverQueued?.call(courseId, upload.mediaId);
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = failure.message;
        _status = 'Uppladdning misslyckades.';
      });
      showSnack(context, failure.message);
      widget.onUploadError?.call(courseId, failure.message);
    }
  }

  String? _resolveMimeType(CoverUploadFile file) {
    final candidate = (file.mimeType ?? '').trim().toLowerCase();
    if (candidate.isNotEmpty) return candidate;
    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final courseReady = widget.courseId != null && widget.courseId!.isNotEmpty;
    final canUpload = courseReady && !_uploading;
    final theme = Theme.of(context);
    final progressVisible = _uploading && _progress > 0;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: Colors.white,
    );
    final bodyStyle = theme.textTheme.bodySmall;
    final secondaryStyle = theme.textTheme.bodySmall;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(18),
      opacity: 0.16,
      borderColor: Colors.white.withValues(alpha: 0.28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kursbild (JPG/PNG/WebP)', style: titleStyle),
          const SizedBox(height: 8),
          Text(
            'Bilden bearbetas och publiceras automatiskt.',
            style: bodyStyle,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: canUpload ? _pickAndUpload : null,
                icon: const Icon(Icons.upload_file),
                label: Text(_selectedFile == null ? 'Valj bild' : 'Byt bild'),
              ),
              if (_selectedFile != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedFile!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: secondaryStyle,
                  ),
                ),
              ],
            ],
          ),
          if (!courseReady) ...[
            const SizedBox(height: 8),
            Text(
              'Spara kursen först för att kunna ladda upp kursbild.',
              style: secondaryStyle,
            ),
          ],
          if (progressVisible) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress),
          ],
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!, style: bodyStyle),
          ],
          if (_error != null && _error!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
