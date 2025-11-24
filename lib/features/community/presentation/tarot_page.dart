import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/core/errors/app_failure.dart';
import 'package:wisdom/features/community/application/community_providers.dart';
import 'package:wisdom/shared/widgets/app_scaffold.dart';
import 'package:wisdom/shared/utils/snack.dart';

class TarotPage extends ConsumerStatefulWidget {
  const TarotPage({super.key});

  @override
  ConsumerState<TarotPage> createState() => _TarotPageState();
}

class _TarotPageState extends ConsumerState<TarotPage> {
  final _question = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(tarotRequestsProvider);
    return requestsAsync.when(
      loading: () => const AppScaffold(
        title: 'Tarot',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppScaffold(
        title: 'Tarot',
        body: Center(child: Text(_friendlyError(error))),
      ),
      data: (items) => AppScaffold(
        title: 'Tarot',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ny förfrågan'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _question,
                      decoration: const InputDecoration(labelText: 'Din fråga'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _sending ? null : _create,
                      child: Text(_sending ? 'Skickar…' : 'Skicka'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (context, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final req = items[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.auto_awesome_rounded),
                      title: Text(req['question'] as String? ?? ''),
                      subtitle: Text('${req['status']} • ${req['created_at']}'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    final text = _question.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final repo = ref.read(communityRepositoryProvider);
      await repo.createTarotRequest(text);
      _question.clear();
      ref.invalidate(tarotRequestsProvider);
      if (!mounted || !context.mounted) return;
      showSnack(context, 'Förfrågan skickad.');
    } catch (error) {
      if (!mounted || !context.mounted) return;
      final friendly = _friendlyError(error);
      showSnack(context, 'Kunde inte skicka: $friendly');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _friendlyError(Object error) {
    final failure = AppFailure.from(error);
    if (failure.kind == AppFailureKind.unauthorized) {
      return 'Logga in för att skicka en förfrågan.';
    }
    return failure.message;
  }
}
