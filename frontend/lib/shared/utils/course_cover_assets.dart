import 'package:flutter/widgets.dart';

import 'package:aveli/shared/utils/backend_assets.dart';

import 'course_cover_assets.g.dart' as generated;

/// Lookup helpers for att hitta lokala kursbilder.
class CourseCoverAssets {
  static String? pathForSlug(String? slug) {
    if (slug == null) return null;
    final path = generated.courseCoverAssets[slug];
    return path == null || path.isEmpty ? null : path;
  }

  static ImageProvider<Object>? resolve({
    required BackendAssetResolver assets,
    String? slug,
    String? coverUrl,
  }) {
    final cover = coverUrl?.trim() ?? '';
    if (cover.isNotEmpty) {
      if (cover.startsWith('http://') || cover.startsWith('https://')) {
        return NetworkImage(cover);
      }
      return assets.imageProvider(cover);
    }
    final path = pathForSlug(slug);
    if (path != null) {
      return assets.imageProvider(path);
    }
    return null;
  }
}
