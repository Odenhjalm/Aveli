import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/features/community/data/messages_repository.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/data/models/message_record.dart';

class MessagesPage extends ConsumerStatefulWidget {
  const MessagesPage({super.key, required this.kind, required this.id});

  /// 'dm' eller 'service'
  final String kind;
  final String id;

  @override
  ConsumerState<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends ConsumerState<MessagesPage> {
  late final MessagesRepository _repo;
  final _input = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  List<MessageRecord> _messages = const [];
  Timer? _poller;

  String get _channel => '${widget.kind}:${widget.id}';

  @override
  void initState() {
    super.initState();
    _repo = MessagesRepository(ref.read(apiClientProvider));
    _load();
    _poller = Timer.periodic(const Duration(seconds: 5), (_) {
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final rows = await _repo.listMessages(_channel);
      if (!mounted) return;
      setState(() {
        _messages = rows;
        _loading = false;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _loading = false);
      final failure = AppFailure.from(error, stackTrace);
      if (!silent) {
        showSnack(context, failure.message);
      }
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _repo.sendMessage(channel: _channel, content: text);
      _input.clear();
      await _load(silent: true);
    } catch (error, stackTrace) {
      if (!mounted) return;
      final failure = AppFailure.from(error, stackTrace);
      showSnack(context, 'Kunde inte skicka: ${failure.message}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authControllerProvider).profile?.id;
    return AppScaffold(
      title: 'Meddelanden',
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final message = _messages[i];
                      final mine = uid != null && message.senderId == uid;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: mine
                                ? Colors.blueAccent.withValues(alpha: .15)
                                : Colors.grey.withValues(alpha: .2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(message.content),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: const InputDecoration(
                      hintText: 'Skriv ett meddelande...',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Skicka'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
