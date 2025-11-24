import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_config.dart';
import 'widgets/mvp_home_page.dart';
import 'widgets/mvp_livekit_page.dart';
import 'widgets/mvp_login_page.dart';
import 'widgets/mvp_profile_page.dart';

class MvpApp extends StatefulWidget {
  const MvpApp({super.key, this.client});

  final MvpApiClient? client;

  @override
  State<MvpApp> createState() => _MvpAppState();
}

class _MvpAppState extends State<MvpApp> {
  late final MvpApiClient _client;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? MvpApiClient(config: MvpAppConfig.auto());
    _client.restoreSession().then((_) => setState(() {}));
  }

  void _handleLogout() {
    _client.logout();
    setState(() {});
  }

  void _handleAuthenticated() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aveli MVP',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: ValueListenableBuilder<String?>(
        valueListenable: _client.accessToken,
        builder: (context, token, _) {
          if (token == null) {
            return MvpLoginPage(client: _client, onSuccess: _handleAuthenticated);
          }
          return Scaffold(
            appBar: AppBar(
              title: const Text('AVELI Studio'),
              actions: [
                IconButton(
                  onPressed: _handleLogout,
                  tooltip: 'Logga ut',
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            body: IndexedStack(
              index: _currentIndex,
              children: [
                MvpHomePage(client: _client),
                MvpProfilePage(client: _client),
                MvpLiveKitPage(client: _client),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _currentIndex,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
                NavigationDestination(icon: Icon(Icons.video_call_outlined), selectedIcon: Icon(Icons.video_call), label: 'Live'),
              ],
              onDestinationSelected: (index) => setState(() => _currentIndex = index),
            ),
          );
        },
      ),
    );
  }
}
