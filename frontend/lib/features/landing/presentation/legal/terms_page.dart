import 'package:flutter/material.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppScaffold(
      title: 'Villkor',
      body: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Allmänna villkor',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Dessa villkor reglerar användningen av tjänsten. '
                    'Denna text är en platshållare – ersätt med juridiskt granskade villkor.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
