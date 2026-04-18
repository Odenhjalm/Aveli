import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:aveli/shared/widgets/media_player.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_extras.dart';
import 'package:aveli/data/models/service.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/application/certification_gate.dart';
import 'package:aveli/core/routing/route_session.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/app_avatar.dart';
import 'package:aveli/features/community/presentation/widgets/profile_logout_section.dart';

class TeacherProfilePage extends ConsumerStatefulWidget {
  const TeacherProfilePage({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<TeacherProfilePage> createState() => _TeacherProfilePageState();
}

class _TeacherProfilePageState extends ConsumerState<TeacherProfilePage> {
  @override
  Widget build(BuildContext context) {
    final asyncProfile = ref.watch(teacherProfileProvider(widget.userId));
    return asyncProfile.when(
      loading: () => const AppScaffold(
        title: 'Lärare',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppScaffold(
        title: 'Lärare',
        body: Center(child: Text(_friendlyError(error))),
      ),
      data: (state) {
        final teacher = state.teacher;
        if (teacher == null) {
          return const AppScaffold(
            title: 'Lärare',
            body: Center(child: Text('Läraren hittades inte.')),
          );
        }
        final profile = (teacher['profile'] as Map?)?.cast<String, dynamic>();
        final display = profile?['display_name'] as String? ?? 'Lärare';
        final avatarPath = profile?['photo_url'] as String? ?? '';
        final config = ref.read(appConfigProvider);
        final resolvedAvatar = _resolveUrl(config.apiBaseUrl, avatarPath);
        final headline = (teacher['headline'] as String?) ?? '';
        final session = ref.watch(routeSessionSnapshotProvider);

        return AppScaffold(
          title: display,
          body: ListView(
            children: [
              Card(
                child: ListTile(
                  leading: AppAvatar(
                    url: resolvedAvatar,
                    size: 48,
                    icon: Icons.person_rounded,
                  ),
                  title: Text(
                    display,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(headline),
                  trailing: FittedBox(
                    child: OutlinedButton(
                      onPressed: () => context.pushNamed(
                        AppRoute.directMessage,
                        pathParameters: {'uid': widget.userId},
                        extra: ChatRouteArgs(
                          peerId: widget.userId,
                          displayName: display,
                        ),
                      ),
                      child: const Text('Meddelande'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _ServicesCard(
                services: state.services,
                isAuthenticated: session.isAuthenticated,
                onRequireLogin: _goToLogin,
              ),
              if (state.profileMedia.items.isNotEmpty) ...[
                const SizedBox(height: 8),
                _ProfileMediaCard(
                  payload: state.profileMedia,
                  onOpenLink: _openExternalLink,
                ),
              ],
              const SizedBox(height: 8),
              _MeditationsCard(meditations: state.meditations),
              const SizedBox(height: 24),
              const ProfileLogoutSection(),
            ],
          ),
        );
      },
    );
  }

  void _goToLogin() {
    if (!mounted) return;
    final router = GoRouter.of(context);
    final redirectTarget = GoRouterState.of(context).uri.toString();
    router.goNamed(
      AppRoute.login,
      queryParameters: {'redirect': redirectTarget},
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    showSnack(context, message);
  }

  Future<void> _openExternalLink(String url) async {
    if (url.isEmpty) return;
    final launched = await launchUrlString(url);
    if (!launched) {
      _showSnack('Kunde inte öppna länken.');
    }
  }

  String _friendlyError(Object error) => AppFailure.from(error).message;

  static String? _resolveUrl(String apiBaseUrl, String? value) {
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return value;
    if (uri.hasScheme) return uri.toString();
    final base = Uri.parse(apiBaseUrl);
    final normalized = value.startsWith('/') ? value : '/$value';
    return base.resolve(normalized).toString();
  }
}

class _ServicesCard extends StatelessWidget {
  const _ServicesCard({
    required this.services,
    required this.isAuthenticated,
    required this.onRequireLogin,
  });

  final List<Service> services;
  final bool isAuthenticated;
  final VoidCallback onRequireLogin;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tjänster',
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (services.isEmpty)
              const Text('Inga tjänster ännu.')
            else
              ...services.map((service) {
                final gate = evaluateCertificationGate(
                  service: service,
                  isAuthenticated: isAuthenticated,
                );
                return _ServiceTile(
                  service: service,
                  gate: gate,
                  onRequireLogin: onRequireLogin,
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _ProfileMediaCard extends StatelessWidget {
  const _ProfileMediaCard({required this.payload, required this.onOpenLink});

  final TeacherProfileMediaPayload payload;
  final Future<void> Function(String url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Utvalt innehall',
              key: const Key('featured_content_title'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ...payload.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _ProfileMediaTile(item: item, onOpenLink: onOpenLink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMediaTile extends StatelessWidget {
  const _ProfileMediaTile({required this.item, required this.onOpenLink});

  final TeacherProfileMediaItem item;
  final Future<void> Function(String url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = item.media;
    final mediaState = media?.state.trim();
    final url = media?.resolvedUrl?.trim();
    final canOpen = url != null && url.isNotEmpty;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        radius: 28,
        child: Icon(Icons.perm_media_outlined),
      ),
      title: Text('Profilmedia', style: theme.textTheme.titleMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Media: ${item.mediaAssetId}', style: theme.textTheme.bodySmall),
          if (mediaState != null && mediaState.isNotEmpty)
            Text('Status: $mediaState', style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Chip(label: Text(item.visibility)),
          if (canOpen) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async => await onOpenLink(url),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Oppna media'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.gate,
    required this.onRequireLogin,
  });

  final Service service;
  final CertificationGateResult gate;
  final VoidCallback onRequireLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final priceLabel = '${(service.priceCents / 100).toStringAsFixed(2)} kr';
    final buttonLabel = gate.pending
        ? 'Kontrollerar behörighet...'
        : gate.requiresAuth
        ? 'Logga in'
        : 'Certifiering krävs';
    final onPressed = gate.pending
        ? null
        : gate.requiresAuth
        ? onRequireLogin
        : null;
    final showLock = !gate.allowed && !gate.pending;

    Widget buttonChild;
    if (gate.pending) {
      buttonChild = const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (showLock) {
      buttonChild = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            gate.requiresAuth ? Icons.lock_open_rounded : Icons.lock_rounded,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(buttonLabel),
        ],
      );
    } else {
      buttonChild = Text(buttonLabel);
    }

    final subtitleChildren = <Widget>[
      if (service.description.isNotEmpty) Text(service.description),
      Text('Pris: $priceLabel', style: t.bodySmall),
      if (gate.pending)
        Text(
          'Kontrollerar behörighet...',
          style: t.bodyMedium?.copyWith(color: theme.colorScheme.tertiary),
        )
      else if (gate.message != null)
        Text(
          gate.message!,
          style: t.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.work_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      service.title,
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (var i = 0; i < subtitleChildren.length; i++) ...[
                      subtitleChildren[i],
                      if (i < subtitleChildren.length - 1)
                        const SizedBox(height: 4),
                    ],
                    if (gate.allowed) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Bokning är inte tillgänglig i appen just nu.',
                        style: t.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (onPressed != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 160),
                child: ElevatedButton(onPressed: onPressed, child: buttonChild),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MeditationsCard extends StatelessWidget {
  const _MeditationsCard({required this.meditations});

  final List<Map<String, dynamic>> meditations;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Meditationer',
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (meditations.isEmpty)
              const Text('Inga meditationer ännu.')
            else
              ...meditations.map(
                (m) => _MeditationTile(
                  title: m['title'] as String? ?? 'Meditation',
                  description: m['description'] as String? ?? '',
                  url:
                      (m['audio_url'] as String?) ??
                      (m['audio_path'] as String? ?? ''),
                  durationSeconds: (m['duration_seconds'] as int?) ?? 0,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MeditationTile extends StatelessWidget {
  const _MeditationTile({
    required this.title,
    required this.description,
    required this.url,
    required this.durationSeconds,
  });

  final String title;
  final String description;
  final String url;
  final int durationSeconds;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final durationHint = durationSeconds > 0
        ? Duration(seconds: durationSeconds)
        : null;
    final hasAudio = url.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(description, style: t.bodySmall),
            ],
            const SizedBox(height: 8),
            if (!hasAudio)
              const Text('Ingen ljudfil uppladdad.')
            else
              InlineAudioPlayer(
                url: url,
                durationHint: durationHint,
                onDownload: () async {
                  await launchUrlString(url);
                },
              ),
          ],
        ),
      ),
    );
  }
}
