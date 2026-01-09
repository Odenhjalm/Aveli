import 'package:flutter/material.dart';

import 'package:aveli/shared/widgets/app_scaffold.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Sidan kunde inte hittas',
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Sidan du försökte öppna finns inte längre eller har flyttats.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
