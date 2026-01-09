import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/payments/application/payments_providers.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_sessions_repository.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/go_router_back_button.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/widgets/glass_container.dart';

class SeminarBookingPage extends ConsumerStatefulWidget {
  const SeminarBookingPage({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<SeminarBookingPage> createState() => _SeminarBookingPageState();
}

class _SeminarBookingPageState extends ConsumerState<SeminarBookingPage> {
  String? _selectedSlotId;
  bool _processingPayment = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(publishedSessionProvider(widget.sessionId));
    final slotsAsync = ref.watch(publicSessionSlotsProvider(widget.sessionId));

    slotsAsync.whenData((slots) {
      if (_selectedSlotId == null && slots.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _selectedSlotId = slots.first.id);
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Boka live-session'),
        leading: const GoRouterBackButton(),
      ),
      body: SafeArea(
        child: sessionAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Fel: $error')),
          data: (session) => _BookingContent(
            session: session,
            slotsAsync: slotsAsync,
            selectedSlotId: _selectedSlotId,
            onSlotSelected: (value) => setState(() => _selectedSlotId = value),
            onCheckout: () => _startCheckout(session),
            processing: _processingPayment,
            errorMessage: _errorMessage,
          ),
        ),
      ),
    );
  }

  Future<void> _startCheckout(StudioSession session) async {
    final slotId = _selectedSlotId;
    if (slotId == null) {
      showSnack(context, 'Välj en slot innan du betalar.');
      return;
    }
    setState(() {
      _processingPayment = true;
      _errorMessage = null;
    });
    try {
      final service = ref.read(stripeCheckoutServiceProvider);
      final result = await service.createSessionCheckout(
        sessionId: session.id,
        sessionSlotId: slotId,
      );
      if (!mounted) return;
      context.push(RoutePath.checkout, extra: result.checkoutUrl);
    } on AppFailure catch (failure) {
      setState(() => _errorMessage = failure.message);
    } catch (error) {
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => _processingPayment = false);
      }
    }
  }
}

class _BookingContent extends StatelessWidget {
  const _BookingContent({
    required this.session,
    required this.slotsAsync,
    required this.selectedSlotId,
    required this.onSlotSelected,
    required this.onCheckout,
    required this.processing,
    required this.errorMessage,
  });

  final StudioSession session;
  final AsyncValue<List<StudioSessionSlot>> slotsAsync;
  final String? selectedSlotId;
  final ValueChanged<String> onSlotSelected;
  final VoidCallback onCheckout;
  final bool processing;
  final String? errorMessage;

  String get _priceLabel {
    final amount = (session.priceCents / 100).toStringAsFixed(2);
    return '$amount ${session.currency.toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (session.description?.isNotEmpty == true)
                  Text(
                    session.description!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Chip(
                      avatar: const Icon(Icons.monetization_on, size: 16),
                      label: Text(_priceLabel),
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      avatar: const Icon(Icons.nightlight_round, size: 16),
                      label: Text(session.isPublished ? 'Publicerad' : 'Draft'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Tillgängliga tider',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          slotsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('Kunde inte läsa slots: $error'),
            data: (slots) {
              if (slots.isEmpty) {
                return const Text('Inga slots publicerade ännu.');
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final slot in slots)
                    ChoiceChip(
                      label: Text(_formatSlot(slot)),
                      selected: selectedSlotId == slot.id,
                      onSelected: (value) {
                        if (value) onSlotSelected(slot.id);
                      },
                      avatar: Icon(
                        slot.isFull ? Icons.event_busy : Icons.event_available,
                        size: 16,
                        color: slot.isFull
                            ? Colors.redAccent
                            : Colors.greenAccent,
                      ),
                      disabledColor: Colors.grey.shade800,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          GradientButton(
            onPressed: processing ? null : onCheckout,
            child: processing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Boka & betala'),
          ),
        ],
      ),
    );
  }

  String _formatSlot(StudioSessionSlot slot) {
    final formatter = DateFormat('EEE d MMM • HH:mm', 'sv_SE');
    final status = slot.isFull ? 'Fullbokad' : 'Platser kvar';
    return '${formatter.format(slot.startAt)} · $status';
  }
}
