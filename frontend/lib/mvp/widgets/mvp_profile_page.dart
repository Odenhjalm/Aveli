import 'package:flutter/material.dart';

import '../../mvp/api_client.dart';

class MvpProfilePage extends StatefulWidget {
  const MvpProfilePage({super.key, required this.client});

  final MvpApiClient client;

  @override
  State<MvpProfilePage> createState() => _MvpProfilePageState();
}

class _MvpProfilePageState extends State<MvpProfilePage> {
  ProfileSummary? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.client.fetchProfile();
      setState(() => _profile = profile);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('Försök igen')),
          ],
        ),
      );
    }
    final profile = _profile;
    if (profile == null) {
      return const Center(child: Text('Ingen profil hittades.'));
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Inloggad som ${profile.displayName}', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('E-post: ${profile.email}'),
                  Text('Roll: ${profile.role}'),
                  Text('User ID: ${profile.userId}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Uppdatera profil'),
          ),
        ],
      ),
    );
  }
}
