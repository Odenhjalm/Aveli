import 'package:flutter/material.dart';

class Gap extends SizedBox {
  const Gap(double h, {super.key}) : super(height: h);
}

class Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const Section({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        if (subtitle != null) ...[
          const Gap(4),
          Text(subtitle!, style: t.bodyMedium),
        ],
        const Gap(12),
        child,
      ],
    );
  }
}

class CardX extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const CardX({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(padding: padding, child: child),
    );
    return onTap == null
        ? card
        : InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: card,
          );
  }
}

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final IconData? icon;
  const PrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
  });
  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon), const SizedBox(width: 8)],
        Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
    return ElevatedButton(onPressed: onPressed, child: child);
  }
}

class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final IconData? icon;
  const SecondaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
  });
  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon), const SizedBox(width: 8)],
        Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
    return OutlinedButton(onPressed: onPressed, child: child);
  }
}
