import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_extras.dart';
import 'package:aveli/features/community/data/messages_repository.dart';
import 'package:aveli/data/models/message_record.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/go_router_back_button.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/widgets/base_page.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final List<MessageRecord> _messages = [];
  final TextEditingController _text = TextEditingController();
  late final MessagesRepository _repo;
  Timer? _poller;

  bool _loading = true;
  bool _sending = false;
  String? _channel;
  String? _peerId;
  String _title = 'Direktmeddelande';

  @override
  void initState() {
    super.initState();
    _repo = MessagesRepository(ref.read(apiClientProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final state = GoRouterState.of(context);
    final extra = state.extra;
    final peer = extra is ChatRouteArgs
        ? extra.peerId
        : state.pathParameters['uid'];
    final name = extra is ChatRouteArgs ? extra.displayName : null;
    final me = ref.read(authControllerProvider).profile?.id;

    if (!mounted) return;

    setState(() {
      _peerId = peer;
      _title = name ?? 'Direktmeddelande';
    });

    if (peer == null || peer.isEmpty || me == null) {
      setState(() => _loading = false);
      return;
    }

    final pair = [me, peer]..sort();
    _channel = 'dm:${pair[0]}:${pair[1]}';

    await _loadMessages();
    if (!mounted) return;
    setState(() => _loading = false);

    _poller = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadMessages(silent: true),
    );
  }

  Future<void> _loadMessages({bool silent = false}) async {
    final channel = _channel;
    if (channel == null) return;

    if (!silent && mounted) {
      setState(() => _loading = true);
    }

    try {
      final rows = await _repo.listMessages(channel);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(rows);
        if (!silent) _loading = false;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      final failure = AppFailure.from(error, stackTrace);
      if (!silent) {
        showSnack(context, failure.message);
      }
      setState(() {
        if (!silent) _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final channel = _channel;
    final me = ref.read(authControllerProvider).profile?.id;
    final text = _text.text.trim();
    if (channel == null || me == null || text.isEmpty) return;

    setState(() => _sending = true);
    try {
      await _repo.sendMessage(channel: channel, content: text);
      _text.clear();
      await _loadMessages(silent: true);
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      if (!mounted) return;
      showSnack(context, 'Kunde inte skicka: ${failure.message}');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).profile;
    final channelMissing = _channel == null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: const GoRouterBackButton(),
        title: Text(_title),
      ),
      body: BasePage(
        child: SafeArea(
          top: false,
          bottom: false,
          child: _buildBody(context, profile, channelMissing),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    Profile? profile,
    bool channelMissing,
  ) {
    if (profile == null || _peerId == null || _peerId!.isEmpty) {
      return const _LoginRequiredView();
    }

    if (channelMissing) {
      return const Center(
        child: Text('Meddelandekanalen kunde inte bestämmas.'),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (context, i) {
              final message = _messages[i];
              final isMe = message.senderId == profile.id;
              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  decoration: const InputDecoration(
                    hintText: 'Skriv ett meddelande…',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GradientButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Skicka'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoginRequiredView extends StatelessWidget {
  const _LoginRequiredView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Logga in för att chatta',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text('Du behöver ett konto för att skicka meddelanden.'),
                const SizedBox(height: 16),
                GradientButton(
                  onPressed: () => context.goNamed(AppRoute.login),
                  child: const Text('Logga in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
