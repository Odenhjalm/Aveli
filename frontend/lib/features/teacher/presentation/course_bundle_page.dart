import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_models.dart';
import 'package:aveli/features/teacher/application/bundle_providers.dart';

class CourseBundlePage extends ConsumerStatefulWidget {
  const CourseBundlePage({super.key});

  @override
  ConsumerState<CourseBundlePage> createState() => _CourseBundlePageState();
}

class _CourseBundlePageState extends ConsumerState<CourseBundlePage> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController(text: '0');
  final _selectedCourses = <String>{};
  final _checkoutBundleIds = <String>{};
  bool _isActive = true;
  bool _submitting = false;

  String _courseSelectionLabel(CourseStudio course) {
    if (course.groupPosition <= 0) {
      return 'Kurs';
    }
    return 'Steg ${course.groupPosition}';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final price = int.tryParse(_priceController.text.replaceAll(' ', '')) ?? 0;
    if (title.isEmpty || price <= 0) {
      showSnack(context, 'Ange titel och paketpris i kronor.');
      return;
    }
    setState(() {
      _submitting = true;
    });
    try {
      final repo = ref.read(courseBundlesRepositoryProvider);
      await repo.createBundle(
        title: title,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        priceAmountCents: price * 100,
        courseIds: _selectedCourses.toList(),
        isActive: _isActive,
      );
      if (!mounted) return;
      ref.invalidate(teacherBundlesProvider);
      showSnack(context, 'Paketet skapades.');
      _titleController.clear();
      _descriptionController.clear();
      _priceController.text = '0';
      _selectedCourses.clear();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      showSnack(context, 'Kunde inte spara paket: $e');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _startBundleCheckout(Map<String, dynamic> bundle) async {
    final bundleId = bundle['id'] as String? ?? '';
    if (bundleId.isEmpty || _checkoutBundleIds.contains(bundleId)) {
      return;
    }

    setState(() => _checkoutBundleIds.add(bundleId));
    try {
      final repo = ref.read(courseBundlesRepositoryProvider);
      final checkout = await repo.createBundleCheckoutSession(bundleId);
      final url = checkout['url'];
      final sessionId = checkout['session_id'];
      final orderId = checkout['order_id'];
      if (url is! String || url.isEmpty) {
        throw StateError('Betalningssvaret saknar betalningsadress.');
      }
      if (sessionId is! String || sessionId.isEmpty) {
        throw StateError('Betalningssvaret saknar sessions-id.');
      }
      if (orderId is! String || orderId.isEmpty) {
        throw StateError('Betalningssvaret saknar order-id.');
      }
      if (!mounted) return;
      context.pushNamed(AppRoute.checkout, extra: url);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, 'Kunde inte starta betalning: $e');
    } finally {
      if (mounted) {
        setState(() => _checkoutBundleIds.remove(bundleId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(myCoursesProvider);
    final bundlesAsync = ref.watch(teacherBundlesProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AppScaffold(
      title: 'Paketpriser',
      showHomeAction: false,
      onBack: () => context.goNamed(AppRoute.teacherHome),
      actions: [
        IconButton(
          tooltip: 'Hem',
          icon: const Icon(Icons.home_outlined),
          onPressed: () => context.goNamed(AppRoute.teacherHome),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Skapa ett paket av flera kurser och starta betalning när paketet ska köpas.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Paketnamn',
                        hintText: 'Till exempel: Introduktionspaket till Aveli',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Beskrivning (valfri)',
                        hintText: 'Vad innehåller paketet?',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Paketpris (kr)',
                        prefixText: 'kr ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _isActive,
                      onChanged: (value) => setState(() => _isActive = value),
                      title: const Text('Aktivt paket'),
                      subtitle: const Text('Aktiva paket kan köpas av elever.'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Välj kurser',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    coursesAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                      error: (error, _) =>
                          Text('Kunde inte hämta kurser: $error'),
                      data: (courses) {
                        if (courses.isEmpty) {
                          return const Text('Du har inga kurser ännu.');
                        }
                        return Column(
                          children: courses.map((course) {
                            final id = course.id;
                            final selected = _selectedCourses.contains(id);
                            return CheckboxListTile(
                              value: selected,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedCourses.add(id);
                                  } else {
                                    _selectedCourses.remove(id);
                                  }
                                });
                              },
                              title: Text(
                                course.title,
                                style: theme.textTheme.bodyLarge,
                              ),
                              subtitle: Text(_courseSelectionLabel(course)),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: GradientButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Skapa paket'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Mina paket',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            bundlesAsync.when(
              loading: () => const LinearProgressIndicator(minHeight: 2),
              error: (error, _) => Text('Kunde inte läsa paket: $error'),
              data: (bundles) {
                if (bundles.isEmpty) {
                  return const Text('Inga paket skapade ännu.');
                }
                return Column(
                  children: bundles.map((bundle) {
                    final bundleId = bundle['id'] as String? ?? '';
                    final isStarting = _checkoutBundleIds.contains(bundleId);
                    final courses = bundle['courses'] as List? ?? const [];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    bundle['title'] as String? ?? 'Paket',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Icon(
                                  bundle['is_active'] == true
                                      ? Icons.check_circle_outline
                                      : Icons.pause_circle,
                                  color: bundle['is_active'] == true
                                      ? cs.primary
                                      : cs.outline,
                                ),
                              ],
                            ),
                            if ((bundle['description'] as String?)
                                    ?.isNotEmpty ??
                                false) ...[
                              const SizedBox(height: 6),
                              Text(
                                bundle['description'] as String,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            if (courses.isNotEmpty)
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: courses.map((course) {
                                  final c = course as Map<String, dynamic>;
                                  return Chip(
                                    avatar: const Icon(
                                      Icons.menu_book,
                                      size: 16,
                                    ),
                                    label: Text(
                                      c['title'] as String? ?? 'Kurs',
                                    ),
                                  );
                                }).toList(),
                              ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: bundleId.isEmpty || isStarting
                                    ? null
                                    : () => _startBundleCheckout(bundle),
                                icon: isStarting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.payment_outlined),
                                label: Text(
                                  isStarting
                                      ? 'Öppnar betalning...'
                                      : 'Öppna betalning',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
