import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/order.dart';
import 'package:aveli/features/payments/application/payments_providers.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';

class OrderHistoryPage extends ConsumerWidget {
  const OrderHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(orderHistoryProvider);
    return AppScaffold(
      title: 'Mina köp',
      onBack: () => context.goNamed(AppRoute.profile),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(orderHistoryProvider);
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: orders.length,
              separatorBuilder: (context, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final order = orders[index];
                return _OrderCard(order: order);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showSnack(context, 'Kunde inte hämta orderhistorik.');
          });
          return const _EmptyState();
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = order.createdAt ?? order.updatedAt;
    final created = createdAt != null
        ? DateFormat.yMMMd().add_Hm().format(createdAt)
        : 'Datum saknas';
    final amount = NumberFormat.simpleCurrency(
      name: order.currency.toUpperCase(),
    ).format(order.amount);
    final status = order.status.toUpperCase();
    final chips = <Widget>[
      Chip(label: Text(status), visualDensity: VisualDensity.compact),
      if (createdAt != null)
        Chip(
          avatar: const Icon(Icons.calendar_today_rounded, size: 16),
          label: Text(created),
          visualDensity: VisualDensity.compact,
        ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              amount,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(_buildDescription(), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: -8, children: chips),
          ],
        ),
      ),
    );
  }

  String _buildDescription() {
    if (order.courseId != null) {
      return 'Kursköp • Kurs-ID: ${order.courseId}';
    }
    if (order.serviceId != null) {
      return 'Tjänst • Tjänst-ID: ${order.serviceId}';
    }
    return 'Order-ID: ${order.id}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text('Inga köp registrerade ännu.', textAlign: TextAlign.center),
      ),
    );
  }
}
