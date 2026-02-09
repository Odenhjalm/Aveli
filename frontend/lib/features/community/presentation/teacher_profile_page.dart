import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:aveli/shared/widgets/media_player.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/core/routing/route_extras.dart';
import 'package:aveli/data/models/certificate.dart';
import 'package:aveli/data/models/service.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/application/certification_gate.dart';
import 'package:aveli/features/media/application/media_playback_controller.dart';
import 'package:aveli/core/routing/route_session.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/app_avatar.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/shared/widgets/app_network_image.dart';
import 'package:aveli/features/community/presentation/widgets/profile_logout_section.dart';

class TeacherProfilePage extends ConsumerStatefulWidget {
  const TeacherProfilePage({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<TeacherProfilePage> createState() => _TeacherProfilePageState();
}

class _TeacherProfilePageState extends ConsumerState<TeacherProfilePage> {
  bool _buying = false;

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
        final viewerCerts = ref.watch(myCertificatesProvider);

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
              _CertificatesCard(certs: state.certificates),
              const SizedBox(height: 8),
              _ServicesCard(
                services: state.services,
                buying: _buying,
                viewerCertificates: viewerCerts,
                isAuthenticated: session.isAuthenticated,
                onBuy: _buyService,
                onRequireLogin: _goToLogin,
              ),
              if (state.profileMedia.isNotEmpty) ...[
                const SizedBox(height: 8),
                _ProfileMediaCard(
                  items: state.profileMedia,
                  onOpenCourse: _openCourse,
                  onOpenLink: _openExternalLink,
                  onShowMessage: _showSnack,
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

  Future<void> _buyService(Service service) async {
    final gate = evaluateCertificationGate(
      service: service,
      viewerCertificates: ref.read(myCertificatesProvider),
      isAuthenticated: ref.read(routeSessionSnapshotProvider).isAuthenticated,
    );
    if (!gate.allowed) {
      if (gate.requiresAuth) {
        _goToLogin();
      } else if (gate.message != null) {
        _showSnack(gate.message!);
      } else if (gate.pending) {
        _showSnack('Vänta tills behörigheten har kontrollerats.');
      }
      return;
    }
    final price = service.priceCents;
    if (price <= 0) {
      _showSnack('Tjänsten saknar pris och kan inte bokas just nu.');
      return;
    }
    setState(() => _buying = true);
    try {
      final checkoutApi = ref.read(checkoutApiProvider);
      final url = await checkoutApi.startServiceCheckout(serviceId: service.id);
      if (!mounted) return;
      context.push(RoutePath.checkout, extra: url);
    } catch (error) {
      _showSnack('Kunde inte initiera köp: ${_friendlyError(error)}');
    } finally {
      if (mounted) setState(() => _buying = false);
    }
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

  void _openCourse(String slug) {
    if (!mounted || slug.isEmpty) return;
    GoRouter.of(
      context,
    ).pushNamed(AppRoute.course, pathParameters: {'slug': slug});
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

class _CertificatesCard extends StatelessWidget {
  const _CertificatesCard({required this.certs});

  final List<Certificate> certs;

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
              'Certifikat',
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (certs.isEmpty)
              const Text('Inga certifikat publicerade ännu.')
            else
              ...certs.map((c) {
                final details = <String>[
                  'Status: ${_statusLabel(c)}',
                  if ((c.notes ?? '').trim().isNotEmpty) c.notes!.trim(),
                  if ((c.evidenceUrl ?? '').trim().isNotEmpty)
                    'Bevis: ${c.evidenceUrl!.trim()}',
                ];
                return ListTile(
                  leading: Icon(_statusIcon(c), color: _statusColor(c)),
                  title: Text(c.title),
                  subtitle: Text(details.join('\n')),
                  isThreeLine:
                      (c.notes ?? '').trim().isNotEmpty ||
                      (c.evidenceUrl ?? '').trim().isNotEmpty,
                );
              }),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(Certificate certificate) {
    if (certificate.isVerified) return Icons.verified_rounded;
    if (certificate.isPending) return Icons.hourglass_top_rounded;
    if (certificate.isRejected) return Icons.highlight_off_rounded;
    return Icons.description_outlined;
  }

  Color? _statusColor(Certificate certificate) {
    if (certificate.isVerified) return Colors.lightGreen;
    if (certificate.isRejected) return Colors.redAccent;
    if (certificate.isPending) return Colors.orangeAccent;
    return null;
  }

  String _statusLabel(Certificate certificate) {
    switch (certificate.status) {
      case CertificateStatus.pending:
        return 'Under granskning';
      case CertificateStatus.verified:
        return 'Verifierat';
      case CertificateStatus.rejected:
        return 'Avslaget';
      case CertificateStatus.unknown:
        return certificate.statusRaw;
    }
  }
}

class _ServicesCard extends StatelessWidget {
  const _ServicesCard({
    required this.services,
    required this.buying,
    required this.viewerCertificates,
    required this.isAuthenticated,
    required this.onBuy,
    required this.onRequireLogin,
  });

  final List<Service> services;
  final bool buying;
  final AsyncValue<List<Certificate>> viewerCertificates;
  final bool isAuthenticated;
  final Future<void> Function(Service) onBuy;
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
                  viewerCertificates: viewerCertificates,
                  isAuthenticated: isAuthenticated,
                );
                return _ServiceTile(
                  service: service,
                  gate: gate,
                  buying: buying,
                  onBuy: () => onBuy(service),
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
  const _ProfileMediaCard({
    required this.items,
    required this.onOpenCourse,
    required this.onOpenLink,
    required this.onShowMessage,
  });

  final List<TeacherProfileMediaItem> items;
  final void Function(String slug) onOpenCourse;
  final Future<void> Function(String url) onOpenLink;
  final void Function(String message) onShowMessage;

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
              'Utvalt innehåll',
              key: const Key('featured_content_title'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _ProfileMediaTile(
                  item: item,
                  onOpenCourse: onOpenCourse,
                  onOpenLink: onOpenLink,
                  onShowMessage: onShowMessage,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMediaTile extends ConsumerWidget {
  const _ProfileMediaTile({
    super.key,
    required this.item,
    required this.onOpenCourse,
    required this.onOpenLink,
    required this.onShowMessage,
  });

  final TeacherProfileMediaItem item;
  final void Function(String slug) onOpenCourse;
  final Future<void> Function(String url) onOpenLink;
  final void Function(String message) onShowMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final title = _titleFor(item);
    final playback = ref.watch(mediaPlaybackControllerProvider);
    final controller = ref.read(mediaPlaybackControllerProvider.notifier);
    final playable = _resolvePlayable();
    final openAction = _resolveOpenAction();
    final openLabel = _resolveOpenLabel();
    final isActive =
        playable != null &&
        playback.currentMediaId == item.id &&
        playback.isPlaying &&
        playback.mediaType == playable.mediaType;
    final activeUrl = playback.url?.trim();
    final resolvedActiveUrl = activeUrl ?? '';
    final hasUrl = resolvedActiveUrl.isNotEmpty;
    final activeVideoPlayback =
        playable != null &&
            playable.mediaType == MediaPlaybackType.video &&
            hasUrl
        ? tryCreateVideoPlaybackState(
            mediaId: item.id,
            url: resolvedActiveUrl,
            title: title,
            controlsMode: InlineVideoControlsMode.custom,
            controlChrome: InlineVideoControlChrome.hidden,
            minimalUi: false,
          )
        : null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _buildLeading(),
      title: Text(title, style: theme.textTheme.titleMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_subtitleFor(item) != null)
            Text(_subtitleFor(item)!, style: theme.textTheme.bodySmall),
          if ((item.description ?? '').trim().isNotEmpty)
            Text(item.description!.trim(), style: theme.textTheme.bodySmall),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Chip(label: Text(_kindLabel(item.mediaKind))),
          ),
          if (openAction != null || playable != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (openAction != null)
                  OutlinedButton.icon(
                    onPressed: () async => await openAction(),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(openLabel),
                  ),
                if (playable != null)
                  ElevatedButton.icon(
                    onPressed: () async {
                      if (isActive) {
                        controller.stop();
                        return;
                      }
                      try {
                        await controller.play(
                          mediaId: item.id,
                          mediaType: playable.mediaType,
                          url: playable.url,
                          title: title,
                          durationHint: playable.durationHint,
                        );
                      } catch (_) {
                        onShowMessage('Kunde inte starta uppspelning.');
                      }
                    },
                    icon: Icon(isActive ? Icons.stop : Icons.play_arrow),
                    label: Text(isActive ? 'Stoppa' : 'Spela'),
                  ),
              ],
            ),
          ],
          if (isActive && playback.isLoading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (isActive && hasUrl) ...[
            const SizedBox(height: 10),
            if (playable?.mediaType == MediaPlaybackType.audio)
              InlineAudioPlayer(
                url: resolvedActiveUrl,
                title: title,
                durationHint: playable.durationHint,
                autoPlay: true,
              )
            else if (activeVideoPlayback != null)
              InlineVideoPlayer(playback: activeVideoPlayback, autoPlay: true),
          ],
        ],
      ),
    );
  }

  Widget _buildLeading() {
    if ((item.coverImageUrl ?? '').isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 60,
          height: 60,
          child: AppNetworkImage(url: item.coverImageUrl!, fit: BoxFit.cover),
        ),
      );
    }
    IconData icon;
    switch (item.mediaKind) {
      case TeacherProfileMediaKind.lessonMedia:
        icon = Icons.play_circle_outline;
        break;
      case TeacherProfileMediaKind.seminarRecording:
        icon = Icons.mic_none;
        break;
      case TeacherProfileMediaKind.external:
        icon = Icons.link_outlined;
        break;
    }
    return CircleAvatar(radius: 28, child: Icon(icon));
  }

  _PlayableMedia? _resolvePlayable() {
    switch (item.mediaKind) {
      case TeacherProfileMediaKind.lessonMedia:
        final source = item.source.lessonMedia;
        if (source == null) return null;
        final kind = source.kind;
        final url = (source.signedUrl ?? source.downloadUrl)?.trim();
        final mediaType = switch (kind) {
          'audio' => MediaPlaybackType.audio,
          'video' => MediaPlaybackType.video,
          _ => null,
        };
        if (mediaType == null || url == null || url.isEmpty) return null;
        final durationSeconds = source.durationSeconds;
        return _PlayableMedia(
          mediaType: mediaType,
          url: url,
          durationHint: durationSeconds != null
              ? Duration(seconds: durationSeconds)
              : null,
        );
      case TeacherProfileMediaKind.seminarRecording:
        final source = item.source.seminarRecording;
        final url = (source?.assetUrl ?? '').trim();
        if (url.isEmpty) return null;
        return _PlayableMedia(mediaType: MediaPlaybackType.video, url: url);
      case TeacherProfileMediaKind.external:
        return null;
    }
  }

  Future<void> Function()? _resolveOpenAction() {
    switch (item.mediaKind) {
      case TeacherProfileMediaKind.lessonMedia:
        final slug = item.source.lessonMedia?.courseSlug?.trim();
        if (slug == null || slug.isEmpty) return null;
        return () async => onOpenCourse(slug);
      case TeacherProfileMediaKind.seminarRecording:
        final url = (item.source.seminarRecording?.assetUrl ?? '').trim();
        if (url.isEmpty) return null;
        return () async => onOpenLink(url);
      case TeacherProfileMediaKind.external:
        final url = item.externalUrl?.trim();
        if (url == null || url.isEmpty) return null;
        return () async => onOpenLink(url);
    }
  }

  String _resolveOpenLabel() {
    switch (item.mediaKind) {
      case TeacherProfileMediaKind.lessonMedia:
        return 'Visa kurs';
      case TeacherProfileMediaKind.seminarRecording:
        return 'Öppna';
      case TeacherProfileMediaKind.external:
        return 'Öppna länk';
    }
  }

  static String _titleFor(TeacherProfileMediaItem item) {
    if ((item.title ?? '').trim().isNotEmpty) return item.title!.trim();
    switch (item.mediaKind) {
      case TeacherProfileMediaKind.lessonMedia:
        return item.source.lessonMedia?.lessonTitle ?? 'Lektionsmedia';
      case TeacherProfileMediaKind.seminarRecording:
        return item.source.seminarRecording?.seminarTitle ?? 'Livesändning';
      case TeacherProfileMediaKind.external:
        return item.externalUrl ?? 'Extern länk';
    }
  }

  static String? _subtitleFor(TeacherProfileMediaItem item) {
    switch (item.mediaKind) {
      case TeacherProfileMediaKind.lessonMedia:
        final course = item.source.lessonMedia?.courseTitle;
        if (course == null || course.isEmpty) return null;
        return 'Från kursen $course';
      case TeacherProfileMediaKind.seminarRecording:
        return 'Inspelning · ${item.source.seminarRecording?.status ?? 'okänd status'}';
      case TeacherProfileMediaKind.external:
        return item.externalUrl;
    }
  }

  static String _kindLabel(TeacherProfileMediaKind kind) {
    switch (kind) {
      case TeacherProfileMediaKind.lessonMedia:
        return 'Lektion';
      case TeacherProfileMediaKind.seminarRecording:
        return 'Livesändning';
      case TeacherProfileMediaKind.external:
        return 'Extern';
    }
  }
}

class _PlayableMedia {
  const _PlayableMedia({
    required this.mediaType,
    required this.url,
    this.durationHint,
  });

  final MediaPlaybackType mediaType;
  final String url;
  final Duration? durationHint;
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.gate,
    required this.buying,
    required this.onBuy,
    required this.onRequireLogin,
  });

  final Service service;
  final CertificationGateResult gate;
  final bool buying;
  final Future<void> Function() onBuy;
  final VoidCallback onRequireLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final priceLabel = '${(service.priceCents / 100).toStringAsFixed(2)} kr';
    final isBusy = buying || gate.pending;
    final buttonLabel = gate.pending
        ? 'Kontrollerar behörighet...'
        : gate.requiresAuth
        ? 'Logga in för att boka'
        : gate.allowed
        ? 'Boka – $priceLabel'
        : 'Certifiering krävs';
    final onPressed = gate.pending
        ? null
        : gate.requiresAuth
        ? onRequireLogin
        : gate.allowed && !buying
        ? onBuy
        : null;
    final showLock = !gate.allowed && !gate.pending;

    Widget buttonChild;
    if (isBusy) {
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
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 160),
              child: ElevatedButton(onPressed: onPressed, child: buttonChild),
            ),
          ),
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
