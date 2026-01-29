// lib/ui/pages/landing_page.dart
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
// ignore_for_file: use_build_context_synchronously
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/landing/application/landing_providers.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/hero_badge.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/utils/course_cover_assets.dart';
import 'package:aveli/shared/widgets/app_avatar.dart';
import 'package:aveli/shared/widgets/card_text.dart';
import 'package:aveli/shared/theme/design_tokens.dart';
import 'package:aveli/shared/widgets/semantic_text.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';

const _aveliPrimaryGradient = LinearGradient(
  colors: [kBrandTurquoise, kBrandAzure, kBrandLilac],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const Size _backgroundImageSize = Size(1536, 1024);

class LandingPage extends ConsumerStatefulWidget {
  const LandingPage({super.key});

  @override
  ConsumerState<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends ConsumerState<LandingPage>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  double _offset = 0.0;
  // Bakgrundsmotivet ligger inbakat i appen för att WebView inte ska kräva API-token.
  final ImageProvider<Object> _bg = AppImages.background;

  // 🔒 säkerställ att vi bara precachar en gång, och först när inherited widgets finns
  bool _didPrecache = false;

  // Data for sections
  bool _loading = true;
  LandingSectionState _popularCourses = const LandingSectionState(items: []);
  LandingSectionState _teachers = const LandingSectionState(items: []);
  LandingSectionState _services = const LandingSectionState(items: []);
  LandingSectionState _introCourses = const LandingSectionState(items: []);

  List<Map<String, dynamic>> get _popularItems => _popularCourses.items;
  List<Map<String, dynamic>> get _teacherItems =>
      _dedupeTeachers(_teachers.items);
  List<Map<String, dynamic>> get _serviceItems => _services.items;

  bool get _isLandingDomain {
    final host = Uri.base.host.toLowerCase();
    return host == 'aveli.app' || host == 'www.aveli.app';
  }

  Future<void> _openAppPath(String path) async {
    final normalized = path.startsWith('/') ? path : '/$path';
    if (_isLandingDomain) {
      final target = 'https://app.aveli.app$normalized';
      final launched = await launchUrlString(
        target,
        mode: LaunchMode.platformDefault,
      );
      if (launched) return;
    }
    if (!mounted) return;
    context.push(normalized);
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      setState(() => _offset = _scroll.offset.clamp(0.0, 400.0));
    });
    // kick off data load
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ precache här (inte i initState) för att undvika “dependOnInheritedWidget”–felet
    if (!_didPrecache) {
      precacheImage(_bg, context);
      _didPrecache = true;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final popularFuture = ref.read(popularCoursesProvider.future);
      final introFuture = ref.read(introCoursesProvider.future);
      final servicesFuture = ref.read(recentServicesProvider.future);
      final teachersFuture = ref.read(teachersProvider.future);
      final myStudioFuture = ref.read(myStudioCoursesProvider.future);

      final popular = await popularFuture;
      final intros = await introFuture;
      final services = await servicesFuture;
      final teachers = await teachersFuture;
      final myStudio = await myStudioFuture;
      final teacherItems = _dedupeTeachers(
        teachers.items
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: true),
      );

      final teachersWithOden = LandingSectionState(
        items: teacherItems,
        errorMessage: teachers.errorMessage,
        devHint: teachers.devHint,
      );
      if (!mounted) return;
      setState(() {
        _popularCourses = _mergePopularWithMyCourses(popular, myStudio);
        _introCourses = intros;
        _services = services;
        _teachers = teachersWithOden;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _dedupeTeachers(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return items;
    final deduped = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final item in items) {
      final rawProfile = item['profile'];
      final profile = rawProfile is Map
          ? rawProfile
          : const <String, dynamic>{};
      final rawUserId = profile['user_id'] ?? item['user_id'];
      final userId = rawUserId?.toString().trim() ?? '';
      if (userId.isEmpty) {
        deduped.add(item);
        continue;
      }
      if (seen.add(userId)) {
        deduped.add(item);
      }
    }
    return deduped;
  }

  LandingSectionState _mergePopularWithMyCourses(
    LandingSectionState popular,
    LandingSectionState myCourses,
  ) {
    final combined = <Map<String, dynamic>>[];
    final seen = <String>{};

    String keyFor(Map<String, dynamic> map) {
      final slug = (map['slug'] as String?)?.trim();
      if (slug != null && slug.isNotEmpty) return slug;
      final id = (map['id'] as String?)?.trim();
      if (id != null && id.isNotEmpty) return id;
      return map.hashCode.toString();
    }

    void addCourse(Map<String, dynamic> map) {
      final key = keyFor(map);
      if (seen.contains(key)) return;
      seen.add(key);
      combined.add(Map<String, dynamic>.from(map));
    }

    final ownCourses = myCourses.items
        .where((course) => course['is_published'] == true)
        .toList(growable: false);

    if (ownCourses.isNotEmpty) {
      for (final course in ownCourses) {
        addCourse(course);
      }
      _normalizeCourseCovers(combined);
      return LandingSectionState(
        items: combined,
        errorMessage: popular.errorMessage,
        devHint: popular.devHint,
      );
    }

    for (final course in popular.items) {
      addCourse(course);
    }

    _normalizeCourseCovers(combined);

    return LandingSectionState(
      items: combined,
      errorMessage: popular.errorMessage,
      devHint: popular.devHint,
    );
  }

  void _normalizeCourseCovers(List<Map<String, dynamic>> courses) {
    for (final course in courses) {
      final cover = course['cover_url'] as String?;
      if (cover == null || cover.isEmpty) continue;
      final resolved = _resolveCoverUrl(cover);
      course['cover_url'] = resolved;
    }
  }

  String _resolveCoverUrl(String value) {
    if (value.isEmpty) return value;
    final config = ref.read(appConfigProvider);
    final base = Uri.parse(config.apiBaseUrl);
    final uri = Uri.tryParse(value);
    if (uri == null) return value;
    if (uri.hasScheme) return value;
    final normalized = value.startsWith('/') ? value : '/$value';
    return base.resolve(normalized).toString();
  }

  void _openIntroModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final items = _introCourses.items;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .78),
                border: const Border(
                  top: BorderSide(color: Colors.transparent),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.school, color: Color(0xDD000000)),
                          const SizedBox(width: 8),
                          const Text(
                            'Introduktionskurser',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Inga introduktionskurser ännu.'),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (context, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final c = items[i];
                            final title =
                                (c['title'] as String?) ?? 'Introduktion';
                            return ListTile(
                              leading: const Icon(Icons.play_circle_outline),
                              title: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Chip(label: Text('Intro')),
                              onTap: () {
                                Navigator.of(context).pop();
                                final slug = (c['slug'] as String?) ?? '';
                                if (slug.isNotEmpty) {
                                  context.pushNamed(
                                    AppRoute.course,
                                    pathParameters: {'slug': slug},
                                  );
                                } else {
                                  context.pushNamed(AppRoute.courseIntro);
                                }
                              },
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _startLandingMembershipCheckout(BuildContext context) async {
    if (!_ensureAuthenticatedForCheckout(context)) return;
    try {
      final url = await ref
          .read(checkoutApiProvider)
          .startMembershipCheckout(interval: 'month');
      if (!mounted) return;
      context.push(RoutePath.checkout, extra: url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte starta medlemskap: $e')),
      );
    }
  }

  bool _ensureAuthenticatedForCheckout(BuildContext context) {
    final authState = ref.read(authControllerProvider);
    if (authState.isAuthenticated) return true;
    context.goNamed(
      AppRoute.signup,
      queryParameters: {'redirect': RoutePath.subscribe},
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final isLightMode = theme.brightness == Brightness.light;
    final config = ref.watch(appConfigProvider);
    final envInfo = ref.watch(envInfoProvider);
    final authState = ref.watch(authControllerProvider);
    final assets = ref.watch(backendAssetResolverProvider);
    final hasEnvIssues = envInfo.hasIssues;
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    // Fokusera bakgrundens huvud mot mitten av logotypen
    final alignX = _legacyAlignXForWidth(size.width);
    final focalX = _computeFocalFromLegacyAlign(
      alignX: alignX,
      viewportSize: size,
    );
    final pixelNudgeX = _pixelNudgeForWidth(size.width);
    final f = size.width >= 900 ? 0.20 : 0.14;
    final baseYOffset = size.width >= 900 ? -80.0 : -40.0;
    final y = baseYOffset - (_offset.clamp(0.0, 120.0)) * f;
    final topScrimOpacity = size.width >= 900 ? 0.30 : 0.34;
    final imgScale = size.width >= 1200
        ? 1.06
        : (size.width >= 900 ? 1.08 : 1.12);
    final logoSize = size.width >= 900 ? 160.0 : 140.0;
    final heroTopSpacing = size.width >= 900 ? 28.0 : 18.0;

    final headerActions = <Widget>[
      if (authState.isAuthenticated) ...[
        TextButton(
          onPressed: () => _openAppPath(RoutePath.home),
          style: TextButton.styleFrom(
            foregroundColor: DesignTokens.headingTextColor,
          ),
          child: const Text('Hem'),
        ),
        TextButton(
          onPressed: () => _openAppPath(RoutePath.profile),
          style: TextButton.styleFrom(
            foregroundColor: DesignTokens.headingTextColor,
          ),
          child: const Text('Profil'),
        ),
      ] else ...[
        TextButton(
          onPressed: hasEnvIssues ? null : () => _openAppPath(RoutePath.login),
          style: TextButton.styleFrom(
            foregroundColor: DesignTokens.headingTextColor,
          ),
          child: const Text('Logga in'),
        ),
        TextButton(
          onPressed: hasEnvIssues ? null : () => _openAppPath(RoutePath.signup),
          style: TextButton.styleFrom(
            foregroundColor: DesignTokens.headingTextColor,
          ),
          child: const Text('Skapa konto'),
        ),
      ],
    ];

    return AppScaffold(
      title: '',
      disableBack: true,
      showHomeAction: false,
      maxContentWidth: 1200,
      contentPadding: EdgeInsets.zero,
      logoSize: logoSize,
      actions: headerActions,
      background: Stack(
        fit: StackFit.expand,
        children: [
          FullBleedBackground(
            image: _bg,
            focalX: focalX,
            pixelNudgeX: pixelNudgeX,
            topOpacity: topScrimOpacity,
            yOffset: y,
            scale: imgScale,
            sideVignette: 0,
            overlayColor: isLightMode
                ? const Color(0xFFFFE2B8).withValues(alpha: 0.10)
                : null,
          ),
          const IgnorePointer(child: _ParticlesLayer()),
        ],
      ),
      body: ListView(
        controller: _scroll,
        padding: EdgeInsets.zero,
        children: [
          // HERO
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Column(
                  children: [
                    SizedBox(height: heroTopSpacing),
                    const SizedBox(height: 16),
                    const HeroHeading(
                      leading: 'Upptäck din andliga',
                      gradientWord: 'resa',
                    ),
                    const SizedBox(height: 10),
                    MetaText(
                      'Lär dig av erfarna andliga lärare genom personliga kurser, '
                      'privata sessioner och djupa lärdomar som förändrar ditt liv.',
                      textAlign: TextAlign.center,
                      baseStyle: t.titleMedium?.copyWith(
                        height: 1.36,
                        letterSpacing: .2,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SectionHeading(
                      'Börja idag',
                      textAlign: TextAlign.center,
                      baseStyle: t.titleLarge,
                      fontWeight: FontWeight.w700,
                    ),
                    const SizedBox(height: 8),
                    // CTA buttons – medlemskap + login
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton(
                          onPressed: hasEnvIssues
                              ? null
                              : () => _startLandingMembershipCheckout(context),
                          child: const Text('Bli medlem'),
                        ),
                        _GradientOutlineButton(
                          label: 'Logga in',
                          onTap: hasEnvIssues
                              ? null
                              : () => _openAppPath(RoutePath.login),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _SocialProofRow(
                      items: [
                        ('Över 1000+', 'nöjda elever'),
                        ('Certifierade', 'lärare'),
                        ('14 dagar', 'pröveperiod'),
                      ],
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
          ),

          // SEKTION – Populära kurser
          Container(
            decoration: const BoxDecoration(color: Colors.transparent),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(
                        child: HeroBadge(
                          text:
                              'Sveriges ledande plattform för andlig utveckling',
                        ),
                      ),
                      const SizedBox(height: 12),
                      const SizedBox(height: 14),
                      SectionHeading(
                        'Populära kurser',
                        baseStyle: t.headlineSmall,
                        fontWeight: FontWeight.w800,
                      ),
                      const SizedBox(height: 4),
                      MetaText(
                        'Se vad andra gillar just nu.',
                        baseStyle: t.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      GlassCard(
                        child: _loading
                            ? const SizedBox(
                                height: 180,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            : _popularItems.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: MetaText('Inga kurser ännu.'),
                              )
                            : LayoutBuilder(
                                builder: (context, c) {
                                  final w = c.maxWidth;
                                  final cross = w >= 900
                                      ? 3
                                      : (w >= 600 ? 2 : 1);
                                  const crossAxisSpacing = 12.0;
                                  const mainAxisSpacing = 12.0;
                                  final availableWidth =
                                      w - crossAxisSpacing * (cross - 1);
                                  final itemWidth = cross == 0
                                      ? w
                                      : availableWidth / cross;
                                  const mediaAspectRatio = 16 / 9;
                                  final mediaHeight =
                                      itemWidth / mediaAspectRatio;
                                  const reservedHeight = 220.0;
                                  final tileHeight =
                                      mediaHeight + reservedHeight;
                                  final computedAspectRatio =
                                      itemWidth / tileHeight;
                                  final childAspectRatio = computedAspectRatio
                                      .clamp(0.78, 1.05)
                                      .toDouble();
                                  return GridView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: _popularItems.length,
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: cross,
                                          crossAxisSpacing: crossAxisSpacing,
                                          mainAxisSpacing: mainAxisSpacing,
                                          childAspectRatio: childAspectRatio,
                                        ),
                                    itemBuilder: (_, i) {
                                      final c = _popularItems[i];
                                      return _CourseTileGlass(
                                        course: c,
                                        index: i,
                                        assets: assets,
                                      );
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // SEKTION – Lärare (carousel)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeading(
                      'Lärare',
                      baseStyle: t.headlineSmall,
                      fontWeight: FontWeight.w800,
                    ),
                    const SizedBox(height: 6),
                    MetaText(
                      'Möt certifierade lärare.',
                      baseStyle: t.bodyLarge,
                    ),
                    const SizedBox(height: 10),
                    GlassCard(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        height: 110,
                        child: _loading
                            ? ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: 6,
                                separatorBuilder: (context, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, _) =>
                                    const _TeacherPillSkeleton(),
                              )
                            : _teacherItems.isEmpty
                            ? const Center(child: MetaText('Inga lärare ännu.'))
                            : ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _teacherItems.length,
                                separatorBuilder: (context, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final map = _teacherItems[index];
                                  final rawUserId =
                                      map['user_id'] ??
                                      (map['profile'] is Map
                                          ? (map['profile'] as Map)['user_id']
                                          : null);
                                  final userId =
                                      rawUserId?.toString().trim() ?? '';
                                  return _TeacherPillData(
                                    key: userId.isEmpty
                                        ? null
                                        : ValueKey(userId),
                                    map: map,
                                    apiBaseUrl: config.apiBaseUrl,
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // SEKTION – Tjänster
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeading(
                      'Tjänster',
                      baseStyle: t.headlineSmall,
                      fontWeight: FontWeight.w800,
                    ),
                    const SizedBox(height: 6),
                    MetaText(
                      'Nya sessioner och läsningar.',
                      baseStyle: t.bodyLarge,
                    ),
                    const SizedBox(height: 10),
                    GlassCard(
                      child: _loading
                          ? const SizedBox(
                              height: 160,
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : _serviceItems.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: MetaText('Inga tjänster ännu.'),
                            )
                          : LayoutBuilder(
                              builder: (context, c) {
                                final w = c.maxWidth;
                                final cross = w >= 900 ? 3 : (w >= 600 ? 2 : 1);
                                return GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _serviceItems.length,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: cross,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                        childAspectRatio: 1.4,
                                      ),
                                  itemBuilder: (_, i) => _ServiceTileGlass(
                                    service: _serviceItems[i],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // CTA-banderoll (bottom)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 44),
                child: Card(
                  color: Colors.white.withValues(alpha: .18),
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: .22),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.workspace_premium_rounded,
                          color: DesignTokens.headingTextColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SectionHeading(
                                '14 dagar pröveperiod',
                                baseStyle: t.titleMedium,
                                fontWeight: FontWeight.w700,
                                maxLines: 2,
                              ),
                              const SizedBox(height: 2),
                              MetaText(
                                'Under pröveperioden får du 14 dagar att testa alla '
                                'introduktionskurser. Därefter 130 kr i månaden.',
                                baseStyle: t.bodyMedium,
                                maxLines: 3,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _PrimaryGradientButton(
                              label: 'Starta pröveperiod',
                              onTap: hasEnvIssues
                                  ? null
                                  : () => _startLandingMembershipCheckout(
                                      context,
                                    ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                            ),
                            _GradientOutlineButton(
                              label: 'Se introduktionskurser',
                              onTap: hasEnvIssues ? null : _openIntroModal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 12,
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
          ),
        ],
      ),
    );
  }

  double _legacyAlignXForWidth(double width) {
    if (width >= 1200) return -0.84;
    if (width >= 900) return -0.82;
    return -0.78;
  }

  double _computeFocalFromLegacyAlign({
    required double alignX,
    required Size viewportSize,
  }) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return 0.5;
    }
    final coverScale = math.max(
      viewportSize.width / _backgroundImageSize.width,
      viewportSize.height / _backgroundImageSize.height,
    );
    if (!coverScale.isFinite || coverScale <= 0) {
      return 0.5;
    }
    final sourceWidth = viewportSize.width / coverScale;
    final targetX =
        _backgroundImageSize.width / 2 +
        alignX * (_backgroundImageSize.width - sourceWidth) / 2;
    return (targetX / _backgroundImageSize.width).clamp(0.0, 1.0);
  }

  double _pixelNudgeForWidth(double width) {
    // Negativ pixel-nudge flyttar motivet åt höger i viewporten.
    if (width >= 1200) return -2.0;
    if (width >= 900) return -3.0;
    return -4.0;
  }
}

/* ---------- Små UI-komponenter i denna fil ---------- */

class _PrimaryGradientButton extends StatelessWidget {
  const _PrimaryGradientButton({
    required this.label,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
  });

  final String label;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(14);
    Widget result = DecoratedBox(
      decoration: BoxDecoration(
        gradient: _aveliPrimaryGradient,
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: kBrandLilac.withAlpha(110),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: DesignTokens.headingTextColor,
                fontWeight: FontWeight.w800,
                letterSpacing: .2,
              ),
            ),
          ),
        ),
      ),
    );

    if (onTap == null) {
      result = Opacity(opacity: 0.5, child: result);
    }

    return SizedBox(height: 48, child: result);
  }
}

class _GradientOutlineButton extends StatelessWidget {
  const _GradientOutlineButton({
    required this.label,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
  });

  final String label;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(999);
    final backgroundColor = Colors.white.withValues(alpha: 0.10);
    final splashColor = Colors.white.withValues(alpha: 0.12);
    final highlightColor = Colors.white.withValues(alpha: 0.06);

    Widget button = Material(
      color: backgroundColor,
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        splashColor: splashColor,
        highlightColor: highlightColor,
        child: Padding(
          padding: padding,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: DesignTokens.headingTextColor,
              fontWeight: FontWeight.w700,
              letterSpacing: .15,
            ),
          ),
        ),
      ),
    );

    if (onTap == null) {
      button = Opacity(opacity: 0.5, child: button);
    }

    return SizedBox(height: 48, child: button);
  }
}

/// Liten, billig partikellayer – subtilt glitter.
class _ParticlesLayer extends StatefulWidget {
  const _ParticlesLayer();

  @override
  State<_ParticlesLayer> createState() => _ParticlesLayerState();
}

class _ParticlesLayerState extends State<_ParticlesLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final _rnd = math.Random();
  final _points = <Offset>[];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // init points once per size
          final size = MediaQuery.of(context).size;
          if (_points.isEmpty) {
            for (var i = 0; i < 60; i++) {
              _points.add(
                Offset(
                  _rnd.nextDouble() * size.width,
                  _rnd.nextDouble() * size.height * .7,
                ),
              );
            }
          }
          return CustomPaint(painter: _ParticlesPainter(_points, _c.value));
        },
      ),
    );
  }
}

class _ParticlesPainter extends CustomPainter {
  final List<Offset> points;
  final double t;
  _ParticlesPainter(this.points, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: .10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    for (var i = 0; i < points.length; i++) {
      final o = points[i];
      final dy = math.sin((t * 2 * math.pi) + i) * 0.6; // flyter sakta
      canvas.drawCircle(Offset(o.dx, o.dy + dy), 1.5, p);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) =>
      oldDelegate.t != t;
}

/// Social proof-raden
class _SocialProofRow extends StatelessWidget {
  final List<(String, String)> items;
  const _SocialProofRow({required this.items});

  @override
  Widget build(BuildContext context) {
    final styleA = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: DesignTokens.headingTextColor,
      fontWeight: FontWeight.w800,
    );
    final styleB = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: DesignTokens.headingTextColor.withValues(alpha: 0.7),
      fontWeight: FontWeight.w600,
    );

    return Wrap(
      spacing: 22,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: items
          .map(
            (e) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.$1, style: styleA),
                const SizedBox(width: 6),
                Text(e.$2, style: styleB),
              ],
            ),
          )
          .toList(),
    );
  }
}

// ---- Section item widgets (glass style) ----

class _CourseTileGlass extends StatelessWidget {
  final Map<String, dynamic> course;
  final int index;
  final BackendAssetResolver assets;
  const _CourseTileGlass({
    required this.course,
    required this.index,
    required this.assets,
  });

  @override
  Widget build(BuildContext context) {
    final title = (course['title'] as String?) ?? 'Kurs';
    final desc = (course['description'] as String?) ?? '';
    final cover = (course['cover_url'] as String?) ?? '';
    final slug = (course['slug'] as String?) ?? '';
    final isIntro = course['is_free_intro'] == true;
    final coverProvider = CourseCoverAssets.resolve(
      assets: assets,
      slug: cover.isEmpty ? slug : null,
      coverUrl: cover,
    );
    final isFallbackLogo = coverProvider == null;
    final imageProvider = coverProvider ?? AppImages.logo;

    final theme = Theme.of(context);
    final baseColor = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.03)
        : Colors.white.withValues(alpha: 0.18);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: DesignTokens.bodyTextColor,
      fontWeight: FontWeight.w800,
    );

    void openCourse() {
      if (slug.isNotEmpty) {
        context.pushNamed(AppRoute.course, pathParameters: {'slug': slug});
      } else {
        context.pushNamed(AppRoute.courseIntro);
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: openCourse,
        borderRadius: BorderRadius.circular(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [baseColor, baseColor.withValues(alpha: 0.32)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF000000).withValues(alpha: 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(isFallbackLogo ? 18 : 0),
                        child: Image(
                          image: imageProvider,
                          fit: isFallbackLogo ? BoxFit.contain : BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                color: Colors.white.withValues(alpha: 0.32),
                                alignment: Alignment.center,
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Image(
                                    image: AppImages.logo,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle,
                                ),
                              ),
                              if (isIntro) const SizedBox(width: 8),
                              if (isIntro)
                                Chip(
                                  label: const Text('Introduktion'),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: theme.colorScheme.primary
                                      .withValues(alpha: 0.18),
                                  labelStyle: theme.textTheme.labelSmall
                                      ?.copyWith(
                                        color: theme.colorScheme.onPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                            ],
                          ),
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            CourseDescriptionText(
                              desc,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              baseStyle: theme.textTheme.bodyMedium,
                            ),
                          ],
                          const Spacer(),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton(
                              onPressed: openCourse,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                minimumSize: const Size(0, 40),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Öppna'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TeacherPillSkeleton extends StatelessWidget {
  const _TeacherPillSkeleton();
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 220,
        height: 90,
        color: Colors.white.withValues(alpha: .3),
      ),
    );
  }
}

class _TeacherPillData extends StatelessWidget {
  final Map<String, dynamic> map;
  final String apiBaseUrl;
  const _TeacherPillData({
    super.key,
    required this.map,
    required this.apiBaseUrl,
  });
  @override
  Widget build(BuildContext context) {
    final rawProfile = (map['profile'] as Map?)?.cast<String, dynamic>() ?? {};
    final merged = rawProfile.isNotEmpty
        ? rawProfile
        : map.cast<String, dynamic>();
    final userId = (map['user_id'] ?? merged['user_id'])?.toString() ?? '';
    final name = (merged['display_name'] as String?) ?? 'Lärare';
    final avatar = (merged['photo_url'] as String?) ?? '';
    final bio = (merged['bio'] as String?) ?? '';
    final resolvedAvatar = _resolveUrl(avatar);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: userId.isEmpty
            ? null
            : () => context.goNamed(
                AppRoute.teacherProfile,
                pathParameters: {'id': userId},
              ),
        borderRadius: BorderRadius.circular(22),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .65),
                border: Border.all(color: Colors.transparent),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppAvatar(url: resolvedAvatar, size: 48),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TeacherNameText(name),
                      if (bio.isNotEmpty)
                        Text(
                          bio,
                          style: const TextStyle(
                            fontSize: 12,
                            color: DesignTokens.mutedTextColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

  String? _resolveUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    final uri = Uri.parse(path);
    if (uri.hasScheme) return uri.toString();
    final base = Uri.parse(apiBaseUrl);
    return base.resolve(path.startsWith('/') ? path : '/$path').toString();
  }
}

class _ServiceTileGlass extends StatelessWidget {
  final Map<String, dynamic> service;
  const _ServiceTileGlass({required this.service});
  @override
  Widget build(BuildContext context) {
    final title = (service['title'] as String?) ?? 'Tjänst';
    final desc = (service['description'] as String?) ?? '';
    final area = (service['certified_area'] as String?) ?? '';
    final cents = (service['price_cents'] as num?)?.toInt();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .80),
          border: Border.all(color: Colors.transparent),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const Spacer(),
            Row(
              children: [
                if (area.isNotEmpty)
                  Chip(label: Text(area), visualDensity: VisualDensity.compact),
                const Spacer(),
                if (cents != null)
                  Text(
                    '${(cents / 100).toStringAsFixed(0)} kr',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
