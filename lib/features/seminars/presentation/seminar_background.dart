import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/shared/utils/backend_assets.dart';

class SeminarBackground extends ConsumerWidget {
  const SeminarBackground({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(backendAssetResolverProvider);
    final image = assets.imageProvider('images/seminar_background.jpg');
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(image: image, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
