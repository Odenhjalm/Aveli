import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/admin/presentation/admin_shell.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});

  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  final _userIdCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _userIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeDestination: AdminShellDestination.users,
      title: 'Users',
      subtitle:
          'Canonical operator mutations for granting and revoking teacher roles.',
      statusChipLabel: 'Canonical role mutations only',
      headerTrailing: IconButton(
        tooltip: 'Clear user id',
        onPressed: _busy
            ? null
            : () {
                _userIdCtrl.clear();
                setState(() {});
              },
        icon: const Icon(Icons.cleaning_services_outlined, color: Colors.white),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: GlassCard(
          padding: const EdgeInsets.all(24),
          opacity: 0.14,
          borderColor: Colors.white.withValues(alpha: 0.12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Teacher role authority',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'There is no request queue or discovery workflow here. Provide the canonical user id and the backend will decide authorization.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.76),
                ),
              ),
              const SizedBox(height: 20),
              _FrostedTextField(
                controller: _userIdCtrl,
                enabled: !_busy,
                label: 'User ID',
                hint: 'Enter the subject UUID',
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: GradientButton(
                      onPressed: _busy ? null : _grantTeacherRole,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Grant teacher role'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _revokeTeacherRole,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                      child: const Text('Revoke teacher role'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Mutations are routed through /admin/users/{user_id}/grant-teacher-role and /admin/users/{user_id}/revoke-teacher-role.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.58),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _grantTeacherRole() async {
    final userId = _userIdCtrl.text.trim();
    if (userId.isEmpty) {
      showSnack(context, 'Enter a user_id before continuing.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).grantTeacherRole(userId);
      if (!mounted) return;
      showSnack(context, 'Teacher role updated.');
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
      showSnack(context, 'Enter a user_id before continuing.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).revokeTeacherRole(userId);
      if (!mounted) return;
      showSnack(context, 'Teacher role updated.');
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

class _FrostedTextField extends StatelessWidget {
  const _FrostedTextField({
    required this.controller,
    required this.enabled,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey<String>('admin-users-user-id-field'),
      controller: controller,
      enabled: enabled,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.42)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
        ),
      ),
    );
  }
}
