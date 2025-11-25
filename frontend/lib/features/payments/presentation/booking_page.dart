import 'package:flutter/material.dart';

import 'package:wisdom/shared/widgets/app_scaffold.dart';

/// Placeholder bookings page – pending REST implementation for booking management.
class BookingPage extends StatelessWidget {
  const BookingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Bokningar',
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Bokningshantering flyttas till nya REST-endpoints. '
            'Funktionen är tillfälligt otillgänglig.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
