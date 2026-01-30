import 'package:flutter/material.dart';

import 'package:aveli/core/bootstrap/boot_log.dart';
import 'package:aveli/core/bootstrap/critical_assets.dart';
import 'package:aveli/shared/theme/design_tokens.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/utils/app_images.dart';

const LinearGradient kAveliBrandGradient = LinearGradient(
  colors: [kBrandTurquoise, kBrandLilac],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    if (!CriticalAssets.logoOk) {
      return SizedBox(width: height, height: height);
    }
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 12),
      child: Image(
        image: AppImages.logo,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          BootLog.criticalAsset(
            name: 'logo',
            status: 'fallback',
            path: AppImages.logoPath,
            error: error,
          );
          return SizedBox(width: height, height: height);
        },
      ),
    );
  }
}

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ShaderMask(
      shaderCallback: (bounds) => kAveliBrandGradient.createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text(
        'Aveli',
        style: (style ?? theme.textTheme.titleMedium)?.copyWith(
          color: DesignTokens.headingTextColor,
          fontWeight: FontWeight.w900,
          letterSpacing: .25,
        ),
      ),
    );
  }
}

class BrandHeaderTitle extends StatelessWidget {
  const BrandHeaderTitle({super.key, this.wordmarkStyle, this.actions});

  final TextStyle? wordmarkStyle;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
          BrandWordmark(style: wordmarkStyle),
          const SizedBox(width: 16),
          if (actions != null)
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: actions),
            ),
        ],
      ),
    );
  }
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.onBrandTap,
    this.logoHeight = 36,
  });

  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final VoidCallback? onBrandTap;
  final double logoHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dividerColor = theme.colorScheme.onSurface.withValues(alpha: 0.22);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 8)],
            BrandLogo(height: logoHeight),
            const SizedBox(width: 10),
            InkWell(
              onTap: onBrandTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: BrandWordmark(style: titleStyle),
              ),
            ),
            if (title.isNotEmpty) ...[
              const SizedBox(width: 12),
              Container(width: 1, height: 18, color: dividerColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
            ] else
              const Spacer(),
            if (actions != null)
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions!,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
