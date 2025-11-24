import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wisdom/core/errors/app_failure.dart';
import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/features/community/application/community_providers.dart';
import 'package:wisdom/shared/utils/snack.dart';
import 'package:wisdom/shared/widgets/app_scaffold.dart';

class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(adminDashboardProvider);
    return dashboard.when(
      loading: () => const AppScaffold(
        title: 'Admin',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppScaffold(
        title: 'Admin',
        body: Center(child: Text(_friendlyError(error))),
      ),
      data: (state) {
        if (!state.isAdmin) {
          return const AppScaffold(
            title: 'Admin',
            body: Center(child: Text('Endast admins.')),
          );
        }
        final t = Theme.of(context).textTheme;
        return AppScaffold(
          title: 'Admin',
          actions: [
            IconButton(
              tooltip: 'Öppna inställningar',
              icon: const Icon(Icons.tune_outlined),
              onPressed: () => context.goNamed(AppRoute.adminSettings),
            ),
          ],
          body: ListView(
            children: [
              Text(
                'Läraransökningar',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (state.requests.isEmpty)
                const Card(
                  child: ListTile(title: Text('Inga ansökningar just nu.')),
                )
              else
                ...state.requests.map((r) {
                  final statusRaw = (r['status'] as String?) ?? 'pending';
                  final status = statusRaw.toLowerCase();
                  final approval = r['approval'] as Map<String, dynamic>?;
                  final subtitleLines = <String>[
                    "Status: $statusRaw",
                    if (r['created_at'] != null) "Skapad: ${r['created_at']}",
                    if (r['updated_at'] != null)
                      "Uppdaterad: ${r['updated_at']}",
                    if ((r['notes'] as String?)?.isNotEmpty == true)
                      r['notes'] as String,
                    if (approval != null &&
                        (approval['approved_at'] as String?)?.isNotEmpty ==
                            true)
                      "Godkänd: ${approval['approved_at']}",
                  ]..removeWhere((line) => line.isEmpty);
                  final isApproved = status == 'verified';
                  final isRejected = status == 'rejected';
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_add_alt_1_rounded),
                      title: Text(r['user_id'] as String? ?? ''),
                      subtitle: Text(subtitleLines.join('\n')),
                      isThreeLine: subtitleLines.length > 1,
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          ElevatedButton(
                            onPressed: _busy || isApproved
                                ? null
                                : () => _approve(r['user_id'] as String),
                            child: const Text('Godkänn'),
                          ),
                          OutlinedButton(
                            onPressed: _busy || isRejected
                                ? null
                                : () => _reject(r['user_id'] as String),
                            child: const Text('Avslå'),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 18),
              Text(
                'Certifikat (granskning)',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (state.certificates.isEmpty)
                const Card(
                  child: ListTile(title: Text('Inga certifikat ännu.')),
                )
              else
                ...state.certificates.map((c) {
                  final statusRaw = (c['status'] as String?) ?? 'pending';
                  final status = statusRaw.toLowerCase();
                  final subtitleLines = <String>[
                    "Användare: ${c['user_id'] ?? ''}",
                    "Status: $statusRaw",
                    if ((c['notes'] as String?)?.isNotEmpty == true)
                      c['notes'] as String,
                    if ((c['evidence_url'] as String?)?.isNotEmpty == true)
                      "Bevis: ${c['evidence_url']}",
                    if (c['updated_at'] != null)
                      "Uppdaterad: ${c['updated_at']}",
                  ]..removeWhere((line) => line.isEmpty);

                  IconData leadingIcon;
                  Color? iconColor;
                  switch (status) {
                    case 'verified':
                      leadingIcon = Icons.verified_rounded;
                      iconColor = Colors.lightGreen;
                      break;
                    case 'rejected':
                      leadingIcon = Icons.highlight_off_rounded;
                      iconColor = Colors.redAccent;
                      break;
                    default:
                      leadingIcon = Icons.hourglass_top_rounded;
                      iconColor = Colors.orangeAccent;
                      break;
                  }

                  return Card(
                    child: ListTile(
                      leading: Icon(leadingIcon, color: iconColor),
                      title: Text(c['title'] as String? ?? 'Certifikat'),
                      subtitle: Text(subtitleLines.join('\n')),
                      isThreeLine: subtitleLines.length > 1,
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          if (status != 'verified')
                            ElevatedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _updateCertificateStatus(
                                      c['id'] as String,
                                      'verified',
                                    ),
                              child: const Text('Verifiera'),
                            ),
                          if (status == 'verified')
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _updateCertificateStatus(
                                      c['id'] as String,
                                      'pending',
                                    ),
                              child: const Text('Återkalla'),
                            ),
                          if (status != 'rejected')
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _updateCertificateStatus(
                                      c['id'] as String,
                                      'rejected',
                                    ),
                              child: const Text('Avslå'),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _approve(String userId) async {
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).approveTeacher(userId);
      ref.invalidate(adminDashboardProvider);
    } catch (error) {
      _showError('Kunde inte godkänna: ${_friendlyError(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(String userId) async {
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).rejectTeacher(userId);
      ref.invalidate(adminDashboardProvider);
    } catch (error) {
      _showError('Kunde inte avslå: ${_friendlyError(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateCertificateStatus(String certId, String status) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .updateCertificateStatus(certificateId: certId, status: status);
      ref.invalidate(adminDashboardProvider);
    } catch (error) {
      _showError('Misslyckades: ${_friendlyError(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showSnack(context, message);
  }

  String _friendlyError(Object error) => AppFailure.from(error).message;
}
