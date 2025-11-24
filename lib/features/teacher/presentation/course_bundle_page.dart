import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/shared/widgets/go_router_back_button.dart';
import 'package:wisdom/shared/widgets/gradient_button.dart';
import 'package:wisdom/shared/utils/snack.dart';
import 'package:wisdom/features/studio/application/studio_providers.dart';
import 'package:wisdom/features/teacher/application/bundle_providers.dart';

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
  bool _isActive = true;
  bool _submitting = false;

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
      ref.invalidate(teacherBundlesProvider);
      showSnack(context, 'Paketet skapades.');
      _titleController.clear();
      _descriptionController.clear();
      _priceController.text = '0';
      _selectedCourses.clear();
      setState(() {});
    } catch (e) {
      showSnack(context, 'Kunde inte spara paket: $e');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(myCoursesProvider);
    final bundlesAsync = ref.watch(teacherBundlesProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: const GoRouterBackButton(),
        title: const Text('Paketpriser'),
        actions: [
          IconButton(
            tooltip: 'Hem',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => context.goNamed(AppRoute.teacherHome),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Skapa ett paket av flera kurser och dela en betalningslänk till dina elever.',
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
                        hintText: 'Ex: Introduktionspaket till Aveli',
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
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    coursesAsync.when(
                      loading: () =>
                          const Padding(
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
                            final id = course['id'] as String?;
                            if (id == null) return const SizedBox.shrink();
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
                                course['title'] as String? ?? 'Kurs',
                                style: theme.textTheme.bodyLarge,
                              ),
                              subtitle: Text(
                                course['is_published'] == true
                                    ? 'Publicerad'
                                    : 'Utkast',
                              ),
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
                                child: CircularProgressIndicator(strokeWidth: 2),
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
              style:
                  theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                    final paymentLink = bundle['payment_link'] as String? ?? '';
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
                            if ((bundle['description'] as String?)?.isNotEmpty ??
                                false) ...[
                              const SizedBox(height: 6),
                              Text(
                                bundle['description'] as String,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: cs.onSurfaceVariant),
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
                                    avatar: const Icon(Icons.menu_book, size: 16),
                                    label: Text(c['title'] as String? ?? 'Kurs'),
                                  );
                                }).toList(),
                              ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    paymentLink.isEmpty
                                        ? 'Ingen länk genererad'
                                        : paymentLink,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Kopiera länk',
                                  icon: const Icon(Icons.copy),
                                  onPressed: paymentLink.isEmpty
                                      ? null
                                      : () async {
                                          await Clipboard.setData(
                                            ClipboardData(text: paymentLink),
                                          );
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text('Länk kopierad'),
                                              ),
                                            );
                                          }
                                        },
                                ),
                              ],
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
