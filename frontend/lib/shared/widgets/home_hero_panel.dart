import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_routes.dart';

class HomeHeroPanel extends StatelessWidget {
  final String? displayName;
  const HomeHeroPanel({super.key, this.displayName});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.transparent),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName == null
                      ? 'Välkommen tillbaka'
                      : 'Hej ${displayName!}',
                  style: t.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: const [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Fortsätt din resa eller utforska fler introduktioner.',
                  style: t.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: .95),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _HeroButton(
                      label: 'Öppna introduktionskurs',
                      onTap: () => context.pushNamed(AppRoute.courseIntro),
                    ),
                    _HeroOutlineButton(
                      label: 'Community',
                      onTap: () => context.pushNamed(AppRoute.community),
                    ),
                    _HeroOutlineButton(
                      label: 'Studio',
                      onTap: () => context.pushNamed(AppRoute.studio),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _HeroButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _HeroOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _HeroOutlineButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.transparent),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
