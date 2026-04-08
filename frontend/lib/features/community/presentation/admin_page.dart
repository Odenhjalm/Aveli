import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  final _userIdCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _userIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Admin',
      actions: [
        IconButton(
          tooltip: 'Admininstallningar',
          icon: const Icon(Icons.tune_outlined),
          onPressed: () => context.goNamed(AppRoute.adminSettings),
        ),
      ],
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Lararroll styrs endast via kanoniska adminmutationer.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Det finns ingen discovery-, request- eller pendingyta har langre. Ange ett user_id direkt for att ge eller ta bort lararrollen. Backend avgor behorigheten.',
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _userIdCtrl,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'User ID',
                      hintText: 'Ange subjectets UUID',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: GradientButton(
                          onPressed: _busy ? null : _grantTeacherRole,
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Ge lararroll'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _revokeTeacherRole,
                          child: const Text('Ta bort lararroll'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _grantTeacherRole() async {
    final userId = _userIdCtrl.text.trim();
    if (userId.isEmpty) {
      showSnack(context, 'Ange ett user_id for att fortsatta.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).grantTeacherRole(userId);
      if (!mounted) return;
      showSnack(context, 'Lararrollen har uppdaterats.');
    } catch (error, stackTrace) {
      if (!mounted) return;
      showSnack(context, AppFailure.from(error, stackTrace).message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _revokeTeacherRole() async {
    final userId = _userIdCtrl.text.trim();
    if (userId.isEmpty) {
      showSnack(context, 'Ange ett user_id for att fortsatta.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).revokeTeacherRole(userId);
      if (!mounted) return;
      showSnack(context, 'Lararrollen har uppdaterats.');
    } catch (error, stackTrace) {
      if (!mounted) return;
      showSnack(context, AppFailure.from(error, stackTrace).message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
