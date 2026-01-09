import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/shared/widgets/top_nav_action_buttons.dart';
import 'package:aveli/widgets/base_page.dart';

const _aveliBrandGradient = LinearGradient(
  colors: [kBrandTurquoise, kBrandLilac],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const _CoursesTab(),
      const _ServicesTab(),
      const _ProfileTab(),
      const _TeachersTab(),
    ];

    final sectionTitle = ['Kurser', 'Tjänster', 'Min profil', 'Lärare'][_index];
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index != 0) {
          setState(() => _index = 0);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        extendBody: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 96,
          leadingWidth: 0,
          titleSpacing: 0,
          leading: const SizedBox.shrink(),
          title: Row(
            children: [
              ShaderMask(
                shaderCallback: (bounds) =>
                    _aveliBrandGradient.createShader(bounds),
                blendMode: BlendMode.srcIn,
                child: Text(
                  'Aveli',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 1,
                height: 18,
                color: Colors.white.withValues(alpha: 0.25),
              ),
              const SizedBox(width: 12),
              Text(
                sectionTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: const [TopNavActionButtons()],
        ),
        body: BasePage(
          child: SafeArea(
            top: false,
            bottom: false,
            child: IndexedStack(index: _index, children: pages),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Kurser',
            ),
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront),
              label: 'Tjänster',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_circle_outlined),
              selectedIcon: Icon(Icons.account_circle),
              label: 'Min profil',
            ),
            NavigationDestination(
              icon: Icon(Icons.school_outlined),
              selectedIcon: Icon(Icons.school),
              label: 'Lärare',
            ),
          ],
        ),
      ),
    );
  }
}

class _TabPlaceholder extends StatelessWidget {
  final String title;
  const _TabPlaceholder({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ProfileTab extends ConsumerWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final profile = auth.profile;

    if (profile == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            child: Padding(
              padding: p20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Logga in',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  gap12,
                  const Text('Du behöver ett konto för att se din profil.'),
                  gap12,
                  GradientButton(
                    onPressed: () => context.goNamed(AppRoute.login),
                    child: const Text('Logga in'),
                  ),
                  gap8,
                  OutlinedButton(
                    onPressed: () => context.goNamed(AppRoute.signup),
                    child: const Text('Skapa konto'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Card(
          child: Padding(
            padding: p20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inloggad som',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                gap6,
                Text(profile.displayName ?? profile.email),
                gap12,
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    GradientButton.icon(
                      onPressed: () => context.pushNamed(AppRoute.profile),
                      icon: const Icon(Icons.person_outline_rounded),
                      label: const Text('Öppna profil'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ref
                            .read(authControllerProvider.notifier)
                            .logout();
                        if (!context.mounted) return;
                        showSnack(context, 'Utloggad');
                        context.goNamed(AppRoute.landing);
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Logga ut'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoursesTab extends StatelessWidget {
  const _CoursesTab();

  @override
  Widget build(BuildContext context) {
    return const _TabPlaceholder(title: 'Kurser');
  }
}

class _ServicesTab extends ConsumerWidget {
  const _ServicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider).profile;
    final config = ref.watch(appConfigProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Card(
          child: Padding(
            padding: p20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tjänster',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                gap8,
                const Text(
                  'Exempel: skapa en order (99 SEK) som stub för betalning.',
                ),
                gap12,
                if (config.subscriptionsEnabled) ...[
                  GradientButton(
                    onPressed: () => context.goNamed(AppRoute.subscribe),
                    child: const Text('Gå till abonnemang'),
                  ),
                  if (profile == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Logga in för att köpa.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                ] else
                  const Text(
                    'Prenumerationer är inte aktiverade ännu.',
                    style: TextStyle(color: Colors.black54),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeachersTab extends StatelessWidget {
  const _TeachersTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Lärare',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          gap12,
          GradientButton.icon(
            onPressed: () => context.goNamed(AppRoute.teacherEditor),
            icon: const Icon(Icons.edit),
            label: const Text('Öppna kurs-editor'),
          ),
        ],
      ),
    );
  }
}
