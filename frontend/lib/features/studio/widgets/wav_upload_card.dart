import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/shared/utils/snack.dart';

import 'wav_upload_source.dart';

class WavUploadCard extends ConsumerStatefulWidget {
  const WavUploadCard({
    super.key,
    required this.courseId,
    required this.lessonId,
    this.onMediaUpdated,
    this.pickFileOverride,
    this.uploadFileOverride,
    this.pollInterval = const Duration(seconds: 5),
  });

  final String? courseId;
  final String? lessonId;
  final Future<void> Function()? onMediaUpdated;
  final Future<WavUploadFile?> Function()? pickFileOverride;
  final Future<void> Function({
    required Uri uploadUrl,
    required Map<String, String> headers,
    required WavUploadFile file,
    required void Function(int sent, int total) onProgress,
  })? uploadFileOverride;
  final Duration pollInterval;

  @override
  ConsumerState<WavUploadCard> createState() => _WavUploadCardState();
}

class _WavUploadCardState extends ConsumerState<WavUploadCard> {
  WavUploadFile? _selectedFile;
  double _progress = 0.0;
  String? _status;
  String? _error;
  String? _mediaId;
  String? _mediaState;
  Timer? _pollTimer;
  bool _uploading = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    final courseId = widget.courseId;
    final lessonId = widget.lessonId;
    if (courseId == null || lessonId == null) {
      showSnack(context, 'Välj kurs och lektion innan du laddar upp WAV.');
      return;
    }

    final picker = widget.pickFileOverride ?? pickWavFile;
    final picked = await picker();
    if (!mounted) return;
    if (picked == null) {
      setState(() => _status = 'Ingen fil vald.');
      return;
    }

    setState(() {
      _selectedFile = picked;
      _progress = 0.0;
      _status = 'Begär uppladdningslänk…';
      _error = null;
      _mediaId = null;
      _mediaState = null;
      _uploading = true;
    });

    try {
      final repo = ref.read(mediaPipelineRepositoryProvider);
      final upload = await repo.requestUploadUrl(
        filename: picked.name,
        mimeType: picked.mimeType ?? 'audio/wav',
        sizeBytes: picked.size,
        mediaType: 'audio',
        courseId: courseId,
        lessonId: lessonId,
      );

      _mediaId = upload.mediaId;
      setState(() => _status = 'Laddar upp WAV…');

      final uploader = widget.uploadFileOverride ?? uploadWavFile;
      await uploader(
        uploadUrl: upload.uploadUrl,
        headers: const {
          'content-type': 'audio/wav',
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
        _status = 'Uppladdad. Bearbetar…';
        _mediaState = 'uploaded';
      });
      await widget.onMediaUpdated?.call();
      _startPolling();
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = failure.message;
        _status = 'Uppladdning misslyckades.';
      });
      showSnack(context, failure.message);
    }
  }

  void _startPolling() {
    final mediaId = _mediaId;
    if (mediaId == null) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(widget.pollInterval, (_) {
      _pollStatus(mediaId);
    });
    _pollStatus(mediaId);
  }

  Future<void> _pollStatus(String mediaId) async {
    try {
      final repo = ref.read(mediaPipelineRepositoryProvider);
      final status = await repo.fetchStatus(mediaId);
      if (!mounted) return;
      setState(() {
        _mediaState = status.state;
        _error = status.errorMessage;
        _status = _statusLabel(status.state);
      });
      if (status.state == 'ready' || status.state == 'failed') {
        _pollTimer?.cancel();
        _pollTimer = null;
        await widget.onMediaUpdated?.call();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  String _statusLabel(String state) {
    switch (state) {
      case 'uploaded':
        return 'Uppladdad. Bearbetas…';
      case 'processing':
        return 'Bearbetas…';
      case 'ready':
        return 'Klar för uppspelning.';
      case 'failed':
        return 'Bearbetningen misslyckades.';
      default:
        return 'Status okänd.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUpload = widget.courseId != null && widget.lessonId != null;
    final theme = Theme.of(context);
    final warningStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white70,
    );
    final progressVisible = _uploading && _progress > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WAV-uppladdning (studiomaster)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'WAV är ett studiomasterformat. Bearbetning kan ta tid.',
              style: warningStyle,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: canUpload && !_uploading ? _pickAndUpload : null,
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                    _selectedFile == null ? 'Välj WAV' : 'Byt WAV-fil',
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
            if (_mediaState != null && _mediaId != null) ...[
              const SizedBox(height: 4),
              Text(
                'Status: $_mediaState',
                style: theme.textTheme.labelSmall,
              ),
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
