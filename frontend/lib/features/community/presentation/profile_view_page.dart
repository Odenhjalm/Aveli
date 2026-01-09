import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/data/follows_repository.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/data/models/service.dart';

class ProfileViewPage extends ConsumerStatefulWidget {
  const ProfileViewPage({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<ProfileViewPage> createState() => _ProfileViewPageState();
}

class _ProfileViewPageState extends ConsumerState<ProfileViewPage> {
  bool _toggling = false;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileViewProvider(widget.userId));
    return profileAsync.when(
      loading: () => const AppScaffold(
        title: 'Profil',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppScaffold(
        title: 'Profil',
        body: Center(child: Text(_friendlyError(error))),
      ),
      data: (state) {
        final profile = state.profile;
        if (profile == null) {
          return const AppScaffold(
            title: 'Profil',
            body: Center(child: Text('Profil hittades inte')),
          );
        }
        final t = Theme.of(context).textTheme;
        final name = (profile['display_name'] as String?) ?? 'Användare';
        final bio = (profile['bio'] as String?) ?? '';
        final List<Service> services = state.services;
        final meditations = state.meditations;
        final following = state.isFollowing;

        return AppScaffold(
          title: name,
          body: ListView(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        child: Icon(Icons.person_rounded),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: t.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (bio.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(bio, style: t.bodyMedium),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _toggling
                            ? null
                            : () => _toggleFollow(following),
                        icon: Icon(
                          following
                              ? Icons.check_rounded
                              : Icons.person_add_alt_1_rounded,
                        ),
                        label: Text(following ? 'Följer' : 'Följ'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tjänster',
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (services.isEmpty)
                        const Text('Inga tjänster.')
                      else
                        ...services.map((service) {
                          final price = (service.priceCents / 100)
                              .toStringAsFixed(2);
                          final theme = Theme.of(context);
                          final t = theme.textTheme;
                          return ListTile(
                            leading: const Icon(Icons.work_rounded),
                            title: Text(service.title),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (service.description.isNotEmpty)
                                  Text(service.description),
                                if (service.requiresCertification)
                                  Text(
                                    'Certifiering krävs för att boka.',
                                    style: t.bodySmall?.copyWith(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('$price kr'),
                                if (service.requiresCertification)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(Icons.lock_rounded, size: 16),
                                  ),
                              ],
                            ),
                            onTap: () => context.pushNamed(
                              AppRoute.serviceDetail,
                              pathParameters: {'id': service.id},
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Meditationer',
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (meditations.isEmpty)
                        const Text('Inga meditationer ännu.')
                      else
                        ...meditations.map(
                          (m) => ListTile(
                            leading: const Icon(Icons.graphic_eq_rounded),
                            title: Text(m['title'] as String? ?? 'Meditation'),
                            subtitle: Text(m['description'] as String? ?? ''),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleFollow(bool currentlyFollowing) async {
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthenticated) {
      if (!mounted) return;
      showSnack(context, 'Logga in för att följa');
      return;
    }
    setState(() => _toggling = true);
    try {
      final repo = FollowsRepository(ref.read(apiClientProvider));
      if (currentlyFollowing) {
        await repo.unfollow(widget.userId);
      } else {
        await repo.follow(widget.userId);
      }
      ref.invalidate(profileViewProvider(widget.userId));
    } catch (error) {
      if (!mounted) return;
      showSnack(context, _friendlyError(error));
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  String _friendlyError(Object error) => AppFailure.from(error).message;
}
