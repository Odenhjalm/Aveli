import 'package:flutter/material.dart';

import 'package:aveli/shared/theme/ui_consts.dart';

class CourseIntroBadge extends StatelessWidget {
  const CourseIntroBadge({super.key, this.label = 'Introduktion'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w800,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: kBrandVibrantGradient),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(label, style: style),
        ),
      ),
    );
  }
}

