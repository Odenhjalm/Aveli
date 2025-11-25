import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisdom/core/errors/app_failure.dart';
import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/data/models/service.dart';
import 'package:wisdom/features/community/application/community_providers.dart';
import 'package:wisdom/shared/widgets/app_scaffold.dart';
import 'package:wisdom/core/routing/route_extras.dart';

class CommunityPage extends ConsumerStatefulWidget {
  const CommunityPage({super.key, this.initialTab});

  final String? initialTab;

  @override
  ConsumerState<CommunityPage> createState() => _CommunityPageState();
}

enum CommunityTab { teachers, services }

class _CommunityPageState extends ConsumerState<CommunityPage> {
  final _q = TextEditingController();
  String _query = '';
  final Set<String> _selectedSpecs = {};
  String _sort = 'rating'; // rating | name | newest
  CommunityTab _activeTab = CommunityTab.teachers;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final desired = _tabFromString(widget.initialTab);
    if (desired != null) {
      _activeTab = desired;
    }
  }

  @override
  void didUpdateWidget(covariant CommunityPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab &&
        widget.initialTab != null) {
      final desired = _tabFromString(widget.initialTab);
      if (desired != null && desired != _activeTab) {
        setState(() => _activeTab = desired);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.initialTab != null) return;
    final tabParam = GoRouterState.of(context).uri.queryParameters['tab'];
    final desired = _tabFromString(tabParam);
    if (desired != null && desired != _activeTab) {
      setState(() => _activeTab = desired);
    }
  }

  @override
  Widget build(BuildContext context) {
    final directory = ref.watch(teacherDirectoryProvider);
    return directory.when(
      loading: () => const AppScaffold(
        title: 'Community',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppScaffold(
        title: 'Community',
        body: Center(child: Text(_friendlyError(error))),
      ),
      data: (state) {
        final children = <Widget>[
          _TabSelector(activeTab: _activeTab, onChanged: _onTabChanged),
          const SizedBox(height: 12),
        ];

        if (_activeTab == CommunityTab.teachers) {
          children.addAll(_teacherSection(state));
        } else {
          final servicesAsync = ref.watch(communityServicesProvider);
          children.add(
            _ServicesCatalog(
              servicesAsync: servicesAsync,
              friendlyError: _friendlyError,
            ),
          );
        }

        return AppScaffold(
          title: 'Community',
          body: ListView(children: children),
        );
      },
    );
  }

  void _onTabChanged(CommunityTab tab) {
    if (_activeTab == tab) return;
    setState(() => _activeTab = tab);
    final tabString = tab == CommunityTab.services ? 'services' : null;
    final currentTab =
        GoRouterState.of(context).uri.queryParameters['tab'] ?? '';
    if ((tabString ?? '') == currentTab) {
      return;
    }
    context.goNamed(
      AppRoute.community,
      queryParameters: tabString == null
          ? const <String, String>{}
          : {'tab': tabString},
      extra: CommunityRouteArgs(initialTab: tabString),
    );
  }

  CommunityTab? _tabFromString(String? value) {
    if (value == 'services') return CommunityTab.services;
    if (value == 'teachers') return CommunityTab.teachers;
    return null;
  }

  List<Widget> _teacherSection(TeacherDirectoryState state) {
    final teachers = _filtered(state.teachers);
    final allSpecs = _allSpecs(state.teachers);
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _q,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Sök lärare, specialitet eller rubrik...',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Sortera:'),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _sort,
                    items: const [
                      DropdownMenuItem(value: 'rating', child: Text('Betyg')),
                      DropdownMenuItem(value: 'name', child: Text('Namn')),
                      DropdownMenuItem(value: 'newest', child: Text('Nyast')),
                    ],
                    onChanged: (v) => setState(() => _sort = v ?? 'rating'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (allSpecs.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...allSpecs.map(
                      (s) => ChoiceChip(
                        label: Text(s),
                        selected: _selectedSpecs.contains(s),
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              _selectedSpecs.add(s);
                            } else {
                              _selectedSpecs.remove(s);
                            }
                          });
                        },
                      ),
                    ),
                    if (_selectedSpecs.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => setState(() => _selectedSpecs.clear()),
                        icon: const Icon(Icons.clear_all_rounded),
                        label: const Text('Rensa filter'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      ...teachers.map(
        (t) => _TeacherListTile(
          teacher: t,
          certCount: state.certCount[t['user_id']] ?? 0,
        ),
      ),
    ];
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> teachers) {
    Iterable<Map<String, dynamic>> list = teachers;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((t) {
        final prof = (t['profile'] as Map?)?.cast<String, dynamic>();
        final name = (prof?['display_name'] as String?)?.toLowerCase() ?? '';
        final head = (t['headline'] as String?)?.toLowerCase() ?? '';
        final specs = ((t['specialties'] as List?)?.cast<String>() ?? const [])
            .join(' ')
            .toLowerCase();
        return name.contains(q) || head.contains(q) || specs.contains(q);
      });
    }
    if (_selectedSpecs.isNotEmpty) {
      list = list.where((t) {
        final specs = ((t['specialties'] as List?)?.cast<String>() ?? const []);
        return _selectedSpecs.every((s) => specs.contains(s));
      });
    }
    final out = list.toList();
    switch (_sort) {
      case 'name':
        out.sort((a, b) {
          final an =
              (((a['profile'] as Map?)
                              ?.cast<String, dynamic>())?['display_name']
                          as String? ??
                      '')
                  .toLowerCase();
          final bn =
              (((b['profile'] as Map?)
                              ?.cast<String, dynamic>())?['display_name']
                          as String? ??
                      '')
                  .toLowerCase();
          return an.compareTo(bn);
        });
        break;
      case 'newest':
        out.sort((a, b) {
          final ad =
              DateTime.tryParse((a['created_at'] as String?) ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bd =
              DateTime.tryParse((b['created_at'] as String?) ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bd.compareTo(ad);
        });
        break;
      case 'rating':
      default:
        out.sort((a, b) {
          final ra = _ratingOf(a);
          final rb = _ratingOf(b);
          return rb.compareTo(ra);
        });
    }
    return out;
  }

  List<String> _allSpecs(List<Map<String, dynamic>> teachers) {
    final s = <String>{};
    for (final t in teachers) {
      final list = (t['specialties'] as List?)?.cast<String>() ?? const [];
      s.addAll(list);
    }
    final out = s.toList()..sort();
    return out;
  }

  double _ratingOf(Map<String, dynamic> t) {
    final r = t['rating'];
    if (r is num) return r.toDouble();
    if (r is String) return double.tryParse(r) ?? 0;
    return 0;
  }

  String _friendlyError(Object error) {
    if (error is AppFailure) return error.message;
    return 'Kunde inte ladda community just nu.';
  }
}

class _TabSelector extends StatelessWidget {
  const _TabSelector({required this.activeTab, required this.onChanged});

  final CommunityTab activeTab;
  final ValueChanged<CommunityTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Utforska', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<CommunityTab>(
              segments: const [
                ButtonSegment(
                  value: CommunityTab.teachers,
                  label: Text('Lärare'),
                  icon: Icon(Icons.school_outlined),
                ),
                ButtonSegment(
                  value: CommunityTab.services,
                  label: Text('Tjänster'),
                  icon: Icon(Icons.storefront_outlined),
                ),
              ],
              selected: <CommunityTab>{activeTab},
              onSelectionChanged: (selection) {
                if (selection.isEmpty) return;
                onChanged(selection.first);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ServicesCatalog extends StatelessWidget {
  const _ServicesCatalog({
    required this.servicesAsync,
    required this.friendlyError,
  });

  final AsyncValue<List<Service>> servicesAsync;
  final String Function(Object error) friendlyError;

  @override
  Widget build(BuildContext context) {
    return servicesAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Kunde inte hämta tjänster: ${friendlyError(error)}'),
        ),
      ),
      data: (services) {
        if (services.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Inga tjänster publicerade ännu.'),
            ),
          );
        }
        return Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: services.length,
            separatorBuilder: (context, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final service = services[index];
              final priceText =
                  '${service.price.toStringAsFixed(2)} ${service.currency.toUpperCase()}';
              return ListTile(
                leading: const Icon(Icons.storefront_rounded),
                title: Text(
                  service.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      priceText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (service.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          service.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (service.requiresCertification)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_user_rounded, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              service.certifiedArea?.isNotEmpty == true
                                  ? 'Kräver certifiering: ${service.certifiedArea}'
                                  : 'Kräver certifiering',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.pushNamed(
                  AppRoute.serviceDetail,
                  pathParameters: {'id': service.id},
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _TeacherListTile extends StatelessWidget {
  const _TeacherListTile({required this.teacher, required this.certCount});

  final Map<String, dynamic> teacher;
  final int certCount;

  @override
  Widget build(BuildContext context) {
    final profile = (teacher['profile'] as Map?)?.cast<String, dynamic>();
    final name = profile?['display_name'] as String? ?? 'Lärare';
    final headline = teacher['headline'] as String? ?? '';
    final specs =
        ((teacher['specialties'] as List?)?.cast<String>() ?? const []).join(
          ' • ',
        );
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person_rounded),
        title: Text(name),
        subtitle: Text(
          [
            if (headline.isNotEmpty) headline,
            if (specs.isNotEmpty) specs,
            if (certCount > 0) '$certCount verifierade certifikat',
          ].where((element) => element.isNotEmpty).join('\n'),
        ),
        trailing: OutlinedButton(
          onPressed: () => context.pushNamed(
            AppRoute.teacherProfile,
            pathParameters: {'id': '${teacher['user_id']}'},
          ),
          child: const Text('Visa profil'),
        ),
      ),
    );
  }
}
