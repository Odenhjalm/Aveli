import 'package:flutter/material.dart';
import 'package:wisdom/shared/widgets/app_scaffold.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppScaffold(
      title: 'Integritetspolicy',
      body: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Integritetspolicy',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Här beskriver vi hur vi samlar in och behandlar personuppgifter. '
                    'Denna text är en platshållare – ersätt med juridiskt granskad policy.',
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
