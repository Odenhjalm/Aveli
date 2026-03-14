import 'package:flutter/material.dart';

class MediaControlDashboard extends StatelessWidget {
  const MediaControlDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Media Control Plane'),
            SizedBox(height: 8),
            Text('Initialization complete'),
          ],
        ),
      ),
    );
  }
}
