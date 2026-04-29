import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/shared/widgets/brand_logo_image.dart';

const _logoAspectRatio = 2.4;

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 150});

  final double size;

  @override
  Widget build(BuildContext context) {
    if (size <= 0) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 18.0, bottom: 12.0),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => GoRouter.of(context).goNamed(AppRoute.landingRoot),
            child: Semantics(
              button: true,
              label: 'Aveli',
              hint: 'Gå till startsidan',
              child: SizedBox(
                height: size,
                width: size * _logoAspectRatio,
                child: BrandLogoImage(
                  height: size,
                  width: size * _logoAspectRatio,
                  semanticLabel: 'Aveli',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
