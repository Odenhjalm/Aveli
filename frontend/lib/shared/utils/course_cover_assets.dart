import 'package:flutter/widgets.dart';

import 'package:aveli/shared/utils/backend_assets.dart';

/// Kursbildsrendering använder bara backendens cover.resolved_url.
class CourseCoverAssets {
  static ImageProvider<Object>? resolve({
    required BackendAssetResolver assets,
    String? slug,
    String? coverUrl,
  }) {
    final resolvedUrl = coverUrl?.trim();
    if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
      return NetworkImage(resolvedUrl);
    }
    return null;
  }
}
