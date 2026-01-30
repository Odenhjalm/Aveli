import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/bootstrap/boot_log.dart';
import 'package:aveli/core/bootstrap/critical_assets.dart';
import 'package:aveli/shared/utils/app_images.dart';

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
                child: CriticalAssets.logoOk
                    ? Image(
                        // Logotypen är bundlad i appen; AssetImage undviker 401-fel från backend.
                        image: AppImages.logo,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) {
                          BootLog.criticalAsset(
                            name: 'logo',
                            status: 'fallback',
                            path: AppImages.logoPath,
                            error: error,
                          );
                          return const Center(
                            child: Text(
                              'Aveli',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 36,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      )
                    : const Center(
                        child: Text(
                          'Aveli',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 36,
                            color: Colors.white,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
