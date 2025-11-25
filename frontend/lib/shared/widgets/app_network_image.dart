import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:wisdom/api/auth_repository.dart';
import 'package:wisdom/shared/utils/image_error_logger.dart';

final _webProtectedImageProvider = FutureProvider.family
    .autoDispose<Uint8List?, String>((ref, url) async {
      final storage = ref.watch(tokenStorageProvider);
      final token = await storage.readAccessToken();
      final headers = <String, String>{
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final uri = Uri.parse(url);
      try {
        final response = await http.get(
          uri,
          headers: headers.isEmpty ? null : headers,
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.bodyBytes;
        }
        throw _WebImageFailure(
          statusCode: response.statusCode,
          url: url,
          message: response.reasonPhrase,
        );
      } on Exception catch (error, stackTrace) {
        return Future<Uint8List?>.error(
          _WebImageFailure(url: url, message: error.toString()),
          stackTrace,
        );
      }
    });

class _WebImageFailure implements Exception {
  const _WebImageFailure({required this.url, this.statusCode, this.message});

  final String url;
  final int? statusCode;
  final String? message;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (status: $statusCode)';
    final msg = message == null ? '' : ' – $message';
    return 'WebImageFailure($url$status$msg)';
  }
}

/// Network image that can attach Authorization header for protected media.
class AppNetworkImage extends ConsumerWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit,
    this.error,
    this.placeholder,
    this.requiresAuth = false,
  });

  final String url;
  final BoxFit? fit;
  final Widget? error;
  final Widget? placeholder;
  final bool requiresAuth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (url.isEmpty) {
      return error ?? const SizedBox.shrink();
    }

    if (kIsWeb) {
      if (requiresAuth) {
        final imageBytes = ref.watch(_webProtectedImageProvider(url));
        return imageBytes.when(
          data: (bytes) {
            if (bytes == null || bytes.isEmpty) {
              return error ?? const SizedBox.shrink();
            }
            return Image.memory(
              bytes,
              fit: fit,
              gaplessPlayback: true,
              errorBuilder: (_, err, stack) {
                ImageErrorLogger.log(
                  source: 'AppNetworkImage(web-memory)',
                  url: url,
                  error: err,
                  stackTrace: stack,
                );
                return error ?? const SizedBox.shrink();
              },
            );
          },
          loading: () => placeholder ?? const SizedBox.shrink(),
          error: (err, stack) {
            ImageErrorLogger.log(
              source: 'AppNetworkImage(web-auth)',
              url: url,
              error: err,
              stackTrace: stack,
            );
            return error ?? const SizedBox.shrink();
          },
        );
      }
      return Image.network(
        url,
        fit: fit,
        errorBuilder: (_, err, stack) {
          ImageErrorLogger.log(
            source: 'AppNetworkImage',
            url: url,
            error: err,
            stackTrace: stack,
          );
          return error ?? const SizedBox.shrink();
        },
        // No universal placeholder for Image.network; caller can wrap if needed.
      );
    }

    if (!requiresAuth) {
      return Image.network(
        url,
        fit: fit,
        errorBuilder: (_, err, stack) {
          ImageErrorLogger.log(
            source: 'AppNetworkImage',
            url: url,
            error: err,
            stackTrace: stack,
          );
          return error ?? const SizedBox.shrink();
        },
      );
    }

    return FutureBuilder<String?>(
      future: ref.read(tokenStorageProvider).readAccessToken(),
      builder: (context, snapshot) {
        final token = snapshot.data;
        final headers = token == null
            ? null
            : {'Authorization': 'Bearer $token'};
        return Image.network(
          url,
          headers: headers,
          fit: fit,
          errorBuilder: (_, err, stack) {
            ImageErrorLogger.log(
              source: 'AppNetworkImage(auth)',
              url: url,
              error: err,
              stackTrace: stack,
            );
            return error ?? const SizedBox.shrink();
          },
        );
      },
    );
  }
}
