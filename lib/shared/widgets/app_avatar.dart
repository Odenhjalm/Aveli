import 'package:flutter/material.dart';
import 'package:wisdom/shared/widgets/app_network_image.dart';

/// Circular avatar that loads from network and gracefully falls back on error.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.url,
    this.size = 52,
    this.icon = Icons.person_outline,
  });

  final String? url;
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: hasUrl
            ? AppNetworkImage(
                url: url!,
                fit: BoxFit.cover,
                requiresAuth: true,
                error: _fallbackIcon(context),
              )
            : _fallbackIcon(context),
      ),
    );
  }

  Widget _fallbackIcon(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.black54),
    );
  }
}
