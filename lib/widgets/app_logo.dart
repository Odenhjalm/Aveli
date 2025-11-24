import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/shared/utils/app_images.dart';

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
            onTap: () => GoRouter.of(context).goNamed(AppRoute.landing),
            child: Semantics(
              button: true,
              label: 'Aveli',
              hint: 'Gå till startsidan',
              child: SizedBox(
                height: size,
                width: size * _logoAspectRatio,
                child: Image(
                  // Logotypen är bundlad i appen; AssetImage undviker 401-fel från backend.
                  image: AppImages.logo,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
