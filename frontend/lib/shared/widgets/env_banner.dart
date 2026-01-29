import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/env/env_state.dart';

/// Red banner for missing required environment keys.
///
/// IMPORTANT: This widget should be conditionally mounted by a route-aware
/// policy (see GuardContextResolver). Do not mount it globally at app startup,
/// or it can flash before the router context is known.
class EnvBanner extends ConsumerWidget {
  const EnvBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envInfo = ref.watch(envInfoProvider);
    if (!envInfo.hasIssues) return const SizedBox.shrink();

    final message = envInfo.missingKeys.isEmpty
        ? 'API-konfiguration saknas. Lägg till API_BASE_URL via --dart-define (web) '
              'eller en lokal env-fil för att aktivera inloggning.'
        : 'Saknade nycklar: ${envInfo.missingKeys.join(', ')}. '
              'Lägg till dem via --dart-define (web) eller en lokal env-fil för att aktivera inloggning.';

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Card(
              color: const Color(0xFFDC2626).withValues(alpha: 0.92),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
