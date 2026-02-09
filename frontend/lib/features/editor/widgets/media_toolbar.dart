import 'dart:async';
import 'dart:convert';
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:mime/mime.dart' as mime;

import 'file_picker_web.dart' as web_picker;

/// Toolbar that allows inserting media HTML tags into a text editor.
class MediaToolbar extends ConsumerStatefulWidget {
  const MediaToolbar({
    super.key,
    required this.controller,
    this.focusNode,
    this.onUploadComplete,
    this.uploadHandler,
    this.courseId,
    this.lessonId,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final void Function(MediaToolbarResult result)? onUploadComplete;
  final MediaUploadHandler? uploadHandler;
  final String? courseId;
  final String? lessonId;

  @override
  ConsumerState<MediaToolbar> createState() => _MediaToolbarState();
}

class _MediaToolbarState extends ConsumerState<MediaToolbar> {
  bool _isUploading = false;
  bool _isDraggingOver = false;
  String? _statusMessage;
  final List<MediaToolbarResult> _recentUploads = <MediaToolbarResult>[];

  bool get _supportsDesktopDrop {
    if (kIsWeb) return false;
    const desktopTargets = {
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    };
    return desktopTargets.contains(defaultTargetPlatform);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const buttons = [
      _MediaButtonConfig(
        label: '🖼 Bild',
        tooltip: 'Ladda upp bild (.jpg, .png, .webp)',
        type: _MediaType.image,
      ),
      _MediaButtonConfig(
        label: '🎵 Ljud',
        tooltip: 'Ladda upp ljud (.mp3, .wav, .m4a)',
        type: _MediaType.audio,
      ),
      _MediaButtonConfig(
        label: '🎬 Video',
        tooltip: 'Ladda upp video (.mp4, .mov, .webm)',
        type: _MediaType.video,
      ),
    ];

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_supportsDesktopDrop) ...[
          _buildDropRegion(theme),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final button in buttons)
              Tooltip(
                message: button.tooltip,
                child: GradientButton.tonal(
                  onPressed: _isUploading ? null : () => _handleUpload(button),
                  child: Text(
                    button.label,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
          ],
        ),
        if (_isUploading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_statusMessage != null) ...[
          const SizedBox(height: 8),
          Text(_statusMessage!, style: theme.textTheme.labelSmall),
        ],
        if (_recentUploads.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildRecentUploads(theme),
        ],
      ],
    );

    if (!_supportsDesktopDrop) {
      return content;
    }

    return DropTarget(
      onDragEntered: (_) {
        setState(() => _isDraggingOver = true);
      },
      onDragExited: (_) {
        setState(() => _isDraggingOver = false);
      },
      onDragDone: (details) {
        _isDraggingOver = false;
        unawaited(_handleDrop(details));
      },
      child: content,
    );
  }

  Widget _buildDropRegion(ThemeData theme) {
    final borderColor = _isDraggingOver
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.7);
    final backgroundColor = _isDraggingOver
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : theme.colorScheme.surface.withValues(alpha: 0.04);
    final textStyle = theme.textTheme.bodyMedium;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.6),
        color: backgroundColor,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.upload_file_outlined, color: borderColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isDraggingOver
                  ? 'Släpp filerna för att ladda upp.'
                  : 'Dra & släpp mediafiler här eller använd knapparna nedan.',
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentUploads(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Senaste uppladdningar',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _recentUploads
              .map((result) => _buildRecentUploadCard(theme, result))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildRecentUploadCard(ThemeData theme, MediaToolbarResult result) {
    switch (result.mediaType) {
      case MediaToolbarType.image:
        return SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.network(
                    result.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, err, stack) => Container(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      alignment: Alignment.center,
                      child: Builder(
                        builder: (_) {
                          // Log once at build time to avoid extra import here.
                          // ignore: avoid_print
                          debugPrint(
                            '[IMG] MediaToolbar url=${result.url} error=$err',
                          );
                          return Icon(
                            Icons.broken_image_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                result.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        );
      case MediaToolbarType.audio:
      case MediaToolbarType.video:
        return Container(
          width: 220,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.18,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                result.mediaType.icon,
                color: theme.colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      result.mediaType.label,
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }

  Future<void> _handleUpload(_MediaButtonConfig button) async {
    if (kIsWeb) {
      final htmlFiles = await web_picker.pickFilesFromHtml(
        allowedExtensions: button.type.allowedExtensions,
        allowMultiple: true,
        accept: _webAcceptMime(button.type),
      );

      if (!mounted) return;

      if (htmlFiles == null || htmlFiles.isEmpty) {
        setState(() => _statusMessage = 'Ingen fil vald.');
        return;
      }

      final requests = htmlFiles
          .map(
            (file) => _PendingUploadRequest(
              type: button.type,
              file: MediaUploadFile(
                name: file.name,
                bytes: file.bytes,
                mimeType: file.mimeType,
              ),
              courseId: widget.courseId,
              lessonId: widget.lessonId,
            ),
          )
          .toList();

      await _uploadRequests(requests);
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: button.type.allowedExtensions,
      allowMultiple: true,
      withData: kIsWeb,
    );

    if (!mounted) return;

    if (picked == null || picked.files.isEmpty) {
      setState(() => _statusMessage = 'Ingen fil vald.');
      return;
    }

    final requests = <_PendingUploadRequest>[];
    final skipped = <String>[];

    for (final file in picked.files) {
      final pending = _pendingFileFromPlatformFile(file);
      if (pending == null) {
        skipped.add(file.name);
        continue;
      }
      requests.add(
        _PendingUploadRequest(
          type: button.type,
          file: pending,
          courseId: widget.courseId,
          lessonId: widget.lessonId,
        ),
      );
    }

    if (requests.isEmpty) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final message = skipped.isEmpty
          ? 'Kunde inte läsa de valda filerna.'
          : 'Kunde inte läsa ${skipped.length} filer.';
      setState(() => _statusMessage = message);
      messenger?.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    await _uploadRequests(requests);

    if (mounted && skipped.isNotEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            skipped.length == 1
                ? 'En fil hoppades över då den saknade läsbar källa.'
                : '${skipped.length} filer hoppades över då de saknade läsbar källa.',
          ),
        ),
      );
    }
  }

  String? _webAcceptMime(_MediaType type) {
    switch (type) {
      case _MediaType.image:
        return 'image/*';
      case _MediaType.audio:
        return 'audio/*';
      case _MediaType.video:
        return 'video/*';
    }
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final droppedFiles = details.files;
    if (droppedFiles.isEmpty) {
      setState(() => _statusMessage = 'Ingen fil släpptes.');
      return;
    }

    final requests = <_PendingUploadRequest>[];
    final unsupported = <String>[];

    for (final file in droppedFiles) {
      final type = _mediaTypeForFileName(file.name);
      if (type == null) {
        unsupported.add(file.name);
        continue;
      }
      final pending = await _pendingFileFromXFile(file);
      if (pending == null) {
        unsupported.add(file.name);
        continue;
      }
      requests.add(
        _PendingUploadRequest(
          type: type,
          file: pending,
          courseId: widget.courseId,
          lessonId: widget.lessonId,
        ),
      );
    }

    if (requests.isEmpty) {
      final message = unsupported.isEmpty
          ? 'Inga filer kunde laddas upp.'
          : 'Filerna stöds inte: ${unsupported.join(', ')}';
      setState(() => _statusMessage = message);
      messenger?.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    await _uploadRequests(requests);

    if (mounted && unsupported.isNotEmpty) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            unsupported.length == 1
                ? 'En fil hoppades över eftersom formatet inte stöds.'
                : '${unsupported.length} filer hoppades över eftersom formatet inte stöds.',
          ),
        ),
      );
    }
  }

  Future<void> _uploadRequests(List<_PendingUploadRequest> requests) async {
    if (!mounted || requests.isEmpty) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _isUploading = true;
      _statusMessage = requests.length == 1
          ? 'Laddar upp ${requests.first.file.name}...'
          : 'Laddar upp ${requests.length} filer...';
    });

    final successes = <MediaToolbarResult>[];
    final failures = <String>[];

    for (var i = 0; i < requests.length; i++) {
      if (!mounted) return;
      final request = requests[i];
      setState(() {
        _statusMessage =
            'Laddar upp ${request.file.name} (${i + 1}/${requests.length})...';
      });

      try {
        final result = await _uploadSingle(request);
        successes.add(result);
      } on MediaUploadException catch (error) {
        failures.add('${request.file.name}: ${error.message}');
      } catch (error) {
        failures.add('${request.file.name}: $error');
      }
    }

    if (!mounted) return;

    setState(() {
      _isUploading = false;
      if (failures.isEmpty) {
        _statusMessage = successes.isEmpty
            ? 'Ingen fil laddades upp.'
            : 'Media uppladdad (${successes.length}).';
      } else if (successes.isEmpty) {
        _statusMessage = 'Uppladdning misslyckades.';
      } else {
        _statusMessage =
            'Media uppladdad (${successes.length}), ${failures.length} fel.';
      }
    });

    if (successes.isNotEmpty) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            successes.length == 1
                ? 'Media uppladdad.'
                : 'Media uppladdad (${successes.length} filer).',
          ),
        ),
      );
    }

    if (failures.isNotEmpty) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            failures.length == 1
                ? 'Fel vid uppladdning: ${failures.first}'
                : 'Fel vid uppladdning: ${failures.length} filer misslyckades.',
          ),
        ),
      );
    }
  }

  Future<MediaToolbarResult> _uploadSingle(
    _PendingUploadRequest request,
  ) async {
    final handler = widget.uploadHandler;
    MediaUploadResult? handlerResult;

    if (handler != null) {
      final uploadRequest = request.toPublicRequest();
      handlerResult = await handler(uploadRequest);
    }

    String url;
    String? htmlTag;

    if (handlerResult == null) {
      url = await _uploadMedia(request);
      htmlTag = request.type.htmlTagFor(url);
    } else {
      url = handlerResult.url;
      htmlTag = handlerResult.htmlTag;
    }

    htmlTag ??= request.type.htmlTagFor(url);
    _insertAtSelection('$htmlTag\n');

    final result = MediaToolbarResult(
      url: url,
      htmlTag: htmlTag,
      fileName: request.file.name,
      mediaType: request.type.toPublicType(),
      uploadedAt: DateTime.now(),
    );

    if (mounted) {
      setState(() {
        _recentUploads.insert(0, result);
        if (_recentUploads.length > 6) {
          _recentUploads.removeRange(6, _recentUploads.length);
        }
      });
    }

    widget.onUploadComplete?.call(result);
    return result;
  }

  Future<String> _uploadMedia(_PendingUploadRequest request) async {
    final config = ref.read(appConfigProvider);
    final tokens = ref.read(tokenStorageProvider);
    final token = await tokens.readAccessToken();
    if (token == null || token.isEmpty) {
      throw const MediaUploadException(
        'Du måste vara inloggad för att ladda upp media.',
      );
    }

    final baseUri = Uri.parse(config.apiBaseUrl);
    final segments = [
      ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
      'upload',
      'course-media',
    ];
    final uploadUri = baseUri.replace(pathSegments: segments);
    final fields = <String, String>{'type': request.type.apiValue};
    final courseId = request.courseId ?? widget.courseId;
    final lessonId = request.lessonId ?? widget.lessonId;
    final courseIdValue = courseId;
    final lessonIdValue = lessonId;
    final hasCourse = courseIdValue != null && courseIdValue.isNotEmpty;
    final hasLesson = lessonIdValue != null && lessonIdValue.isNotEmpty;
    if (!hasCourse && !hasLesson) {
      throw const MediaUploadException(
        'Kurs eller lektion saknas för uppladdning.',
      );
    }
    if (courseIdValue != null && courseIdValue.isNotEmpty) {
      fields['course_id'] = courseIdValue;
    }
    if (lessonIdValue != null && lessonIdValue.isNotEmpty) {
      fields['lesson_id'] = lessonIdValue;
    }

    final multipart = http.MultipartRequest('POST', uploadUri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields.addAll(fields);

    multipart.files.add(await request.file.toMultipartFile(fieldName: 'file'));

    http.Response response;
    try {
      final streamed = await multipart.send();
      response = await http.Response.fromStream(streamed);
    } on http.ClientException catch (error) {
      throw MediaUploadException('Nätverksfel: ${error.message}');
    } on Object catch (error) {
      throw MediaUploadException('Kunde inte ansluta: $error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = _uploadErrorMessage(response);
      throw MediaUploadException(message);
    }

    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final url = _extractUrl(payload, config.apiBaseUrl);
      if (url == null || url.isEmpty) {
        throw const MediaUploadException('Ogiltigt svar från servern.');
      }
      return url;
    } on MediaUploadException {
      rethrow;
    } on Object {
      throw const MediaUploadException('Ogiltigt svar från servern.');
    }
  }

  String _uploadErrorMessage(http.Response response) {
    final status = response.statusCode;
    final body = response.body;
    if (body.isEmpty) {
      return 'Uppladdning misslyckades (status $status).';
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        for (final key in ['detail', 'message', 'error']) {
          final value = decoded[key];
          if (value is String && value.isNotEmpty) {
            return value;
          }
        }
        final errors = decoded['errors'];
        if (errors is List && errors.isNotEmpty) {
          final firstError = errors.firstWhere(
            (element) => element is String,
            orElse: () => null,
          );
          if (firstError is String && firstError.isNotEmpty) {
            return firstError;
          }
        }
      } else if (decoded is List && decoded.isNotEmpty) {
        final firstMessage = decoded.firstWhere(
          (element) => element is String && element.isNotEmpty,
          orElse: () => null,
        );
        if (firstMessage is String) {
          return firstMessage;
        }
      }
    } catch (_) {
      // Ignore parse errors and fall back to raw body snippet.
    }

    final snippet = body.length > 160 ? '${body.substring(0, 160)}…' : body;
    return 'Uppladdning misslyckades (status $status): $snippet';
  }

  void _insertAtSelection(String snippet) {
    final controller = widget.controller;
    final currentText = controller.text;
    final selection = controller.selection;
    final hasSelection =
        selection.start >= 0 &&
        selection.end >= 0 &&
        selection.start <= currentText.length &&
        selection.end <= currentText.length;
    final start = hasSelection ? selection.start : currentText.length;
    final end = hasSelection ? selection.end : currentText.length;

    final updatedText = currentText.replaceRange(start, end, snippet);
    controller.value = controller.value.copyWith(
      text: updatedText,
      selection: TextSelection.collapsed(offset: start + snippet.length),
      composing: TextRange.empty,
    );
    widget.focusNode?.requestFocus();
  }

  String? _extractUrl(Map<String, dynamic> payload, String baseUrl) {
    final candidate =
        payload['download_url'] ??
        payload['downloadUrl'] ??
        payload['signed_url'] ??
        payload['url'] ??
        payload['path'];
    if (candidate is String && candidate.isNotEmpty) {
      return _resolveUrl(candidate, baseUrl);
    }
    final media = payload['media'];
    if (media is Map<String, dynamic>) {
      final nested =
          media['download_url'] ??
          media['downloadUrl'] ??
          media['signed_url'] ??
          media['url'] ??
          media['path'];
      if (nested is String && nested.isNotEmpty) {
        return _resolveUrl(nested, baseUrl);
      }
    }
    return null;
  }

  String _resolveUrl(String candidate, String baseUrl) {
    final base = Uri.parse(baseUrl);
    final uri = Uri.parse(candidate);
    if (uri.hasScheme) {
      return uri.toString();
    }
    final normalized = candidate.startsWith('/') ? candidate : '/$candidate';
    return base.resolve(normalized).toString();
  }

  MediaUploadFile? _pendingFileFromPlatformFile(PlatformFile platformFile) {
    final bytes = platformFile.bytes;
    final candidatePath = platformFile.path ?? platformFile.name;
    String? inferredMime;
    if (bytes != null && bytes.isNotEmpty) {
      final header = bytes.sublist(0, bytes.length > 12 ? 12 : bytes.length);
      inferredMime =
          mime.lookupMimeType(candidatePath, headerBytes: header) ??
          mime.lookupMimeType(candidatePath);
    } else {
      inferredMime = mime.lookupMimeType(candidatePath);
    }

    if (bytes != null) {
      return MediaUploadFile(
        name: platformFile.name,
        bytes: bytes,
        mimeType: inferredMime,
      );
    }
    final path = platformFile.path;
    if (path != null && path.isNotEmpty) {
      return MediaUploadFile(
        name: platformFile.name,
        path: path,
        mimeType: inferredMime,
      );
    }
    final stream = platformFile.readStream;
    if (stream != null) {
      return MediaUploadFile(
        name: platformFile.name,
        stream: stream,
        mimeType: inferredMime,
      );
    }
    return null;
  }

  Future<MediaUploadFile?> _pendingFileFromXFile(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      return MediaUploadFile(
        name: file.name,
        bytes: bytes,
        mimeType: file.mimeType ?? mime.lookupMimeType(file.name),
      );
    } catch (_) {
      return null;
    }
  }
}

class MediaToolbarResult {
  MediaToolbarResult({
    required this.url,
    required this.htmlTag,
    required this.fileName,
    required this.mediaType,
    DateTime? uploadedAt,
  }) : uploadedAt = uploadedAt ?? DateTime.now();

  final String url;
  final String htmlTag;
  final String fileName;
  final MediaToolbarType mediaType;
  final DateTime uploadedAt;
}

enum MediaToolbarType { image, audio, video }

extension MediaToolbarTypeX on MediaToolbarType {
  String get label {
    switch (this) {
      case MediaToolbarType.image:
        return 'Bild';
      case MediaToolbarType.audio:
        return 'Ljud';
      case MediaToolbarType.video:
        return 'Video';
    }
  }

  IconData get icon {
    switch (this) {
      case MediaToolbarType.image:
        return Icons.image_outlined;
      case MediaToolbarType.audio:
        return Icons.audiotrack_outlined;
      case MediaToolbarType.video:
        return Icons.movie_creation_outlined;
    }
  }
}

enum _MediaType { image, audio, video }

extension _MediaTypeExtension on _MediaType {
  List<String> get allowedExtensions {
    switch (this) {
      case _MediaType.image:
        return const ['jpg', 'jpeg', 'png', 'webp'];
      case _MediaType.audio:
        return const ['mp3', 'wav', 'm4a'];
      case _MediaType.video:
        return const ['mp4', 'mov', 'webm'];
    }
  }

  String get apiValue {
    switch (this) {
      case _MediaType.image:
        return 'image';
      case _MediaType.audio:
        return 'audio';
      case _MediaType.video:
        return 'video';
    }
  }

  MediaToolbarType toPublicType() {
    switch (this) {
      case _MediaType.image:
        return MediaToolbarType.image;
      case _MediaType.audio:
        return MediaToolbarType.audio;
      case _MediaType.video:
        return MediaToolbarType.video;
    }
  }

  String htmlTagFor(String url) {
    switch (this) {
      case _MediaType.image:
        return '<img src="$url" alt="" />';
      case _MediaType.audio:
        return '<audio controls src="$url"></audio>';
      case _MediaType.video:
        return '<video src="$url"></video>';
    }
  }
}

_MediaType? _mediaTypeForFileName(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == fileName.length - 1) {
    return null;
  }
  final ext = fileName.substring(dotIndex + 1).toLowerCase();
  for (final type in _MediaType.values) {
    if (type.allowedExtensions.contains(ext)) {
      return type;
    }
  }
  return null;
}

class _MediaButtonConfig {
  const _MediaButtonConfig({
    required this.label,
    required this.tooltip,
    required this.type,
  });

  final String label;
  final String tooltip;
  final _MediaType type;
}

class _PendingUploadRequest {
  const _PendingUploadRequest({
    required this.type,
    required this.file,
    this.courseId,
    this.lessonId,
  });

  final _MediaType type;
  final MediaUploadFile file;
  final String? courseId;
  final String? lessonId;

  MediaUploadRequest toPublicRequest() => MediaUploadRequest(
    mediaType: type.toPublicType(),
    file: file,
    courseId: courseId,
    lessonId: lessonId,
  );
}

class MediaUploadFile {
  const MediaUploadFile({
    required this.name,
    this.path,
    this.bytes,
    this.stream,
    this.mimeType,
  });

  final String name;
  final String? path;
  final Uint8List? bytes;
  final Stream<List<int>>? stream;
  final String? mimeType;

  Future<http.MultipartFile> toMultipartFile({
    required String fieldName,
  }) async {
    final data = await readAsBytes();
    return http.MultipartFile.fromBytes(
      fieldName,
      data,
      filename: name,
      contentType: _tryParseMediaType(),
    );
  }

  Future<Uint8List> readAsBytes() async {
    if (bytes != null) {
      return bytes!;
    }
    if (stream != null) {
      final chunks = <List<int>>[];
      await for (final chunk in stream!) {
        chunks.add(chunk);
      }
      return Uint8List.fromList(chunks.expand((c) => c).toList());
    }
    if (path != null && path!.isNotEmpty) {
      final xfile = XFile(path!);
      return xfile.readAsBytes();
    }
    throw MediaUploadException('Saknar filinnehåll för $name.');
  }

  MediaType? _tryParseMediaType() {
    final candidate = (mimeType != null && mimeType!.isNotEmpty)
        ? mimeType!
        : mime.lookupMimeType(name);
    if (candidate == null || candidate.isEmpty) {
      return null;
    }
    try {
      return MediaType.parse(candidate);
    } catch (_) {
      return null;
    }
  }
}

class MediaUploadException implements Exception {
  const MediaUploadException(this.message);
  final String message;

  @override
  String toString() => 'MediaUploadException: $message';
}

class MediaUploadRequest {
  const MediaUploadRequest({
    required this.mediaType,
    required this.file,
    this.courseId,
    this.lessonId,
  });

  final MediaToolbarType mediaType;
  final MediaUploadFile file;
  final String? courseId;
  final String? lessonId;
}

class MediaUploadResult {
  const MediaUploadResult({required this.url, this.htmlTag});

  final String url;
  final String? htmlTag;
}

typedef MediaUploadHandler =
    Future<MediaUploadResult> Function(MediaUploadRequest request);
