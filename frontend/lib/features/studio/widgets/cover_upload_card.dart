import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/media/application/media_providers.dart';
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
  final void Function(String mediaId)? onCoverQueued;
  final void Function(String message)? onUploadError;
  final Future<CoverUploadFile?> Function()? pickFileOverride;
  final Future<void> Function({
    required Uri uploadUrl,
    required Map<String, String> headers,
    required CoverUploadFile file,
    required void Function(int sent, int total) onProgress,
  })? uploadFileOverride;

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
    if (widget.courseId == null || widget.courseId!.isEmpty) {
      showSnack(context, 'Valj kurs innan du laddar upp en kursbild.');
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
      widget.onUploadError?.call(message);
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
        courseId: widget.courseId!,
      );

      if (!mounted) return;
      setState(() => _status = 'Laddar upp kursbild...');

      final uploader = widget.uploadFileOverride ?? uploadCoverFile;
      await uploader(
        uploadUrl: upload.uploadUrl,
        headers: {
          'content-type': resolvedMime,
        },
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
      widget.onCoverQueued?.call(upload.mediaId);
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = failure.message;
        _status = 'Uppladdning misslyckades.';
      });
      showSnack(context, failure.message);
      widget.onUploadError?.call(failure.message);
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
    final canUpload = widget.courseId != null && !_uploading;
    final theme = Theme.of(context);
    final progressVisible = _uploading && _progress > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kursbild (JPG/PNG/WebP)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Bilden bearbetas och publiceras automatiskt.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: canUpload ? _pickAndUpload : null,
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                    _selectedFile == null ? 'Valj bild' : 'Byt bild',
                  ),
                ),
                if (_selectedFile != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedFile!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
            if (progressVisible) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _progress),
            ],
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(_status!, style: theme.textTheme.bodySmall),
            ],
            if (_error != null && _error!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
