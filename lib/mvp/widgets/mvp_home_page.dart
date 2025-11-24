import 'package:flutter/material.dart';

import '../../mvp/api_client.dart';

class MvpHomePage extends StatefulWidget {
  const MvpHomePage({super.key, required this.client});

  final MvpApiClient client;

  @override
  State<MvpHomePage> createState() => _MvpHomePageState();
}

class _MvpHomePageState extends State<MvpHomePage> {
  bool _loading = true;
  String? _error;
  List<CourseSummary> _courses = const [];
  List<ServiceSummary> _services = const [];
  List<FeedActivity> _feed = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.client.listMyCourses(),
        widget.client.listActiveServices(),
        widget.client.fetchFeed(limit: 8),
      ]);
      setState(() {
        _courses = results[0] as List<CourseSummary>;
        _services = results[1] as List<ServiceSummary>;
        _feed = results[2] as List<FeedActivity>;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _purchase(ServiceSummary service) async {
    try {
      final order = await widget.client.createOrderForService(service.id);
      final checkoutUrl = await widget.client.createStripeCheckout(
        orderId: order.id,
        successUrl: 'https://example.org/success',
        cancelUrl: 'https://example.org/cancel',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Checkout-session skapad'),
          content: Text('Öppna URL:n i webbläsare för att testa Payment Element:\n$checkoutUrl'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Stäng')),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte skapa order: $error')),
      );
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
            Text('Fel: $_error'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _reload, child: const Text('Försök igen')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Mina kurser',
            child: _courses.isEmpty
                ? const Text('Du är inte inskriven i några kurser än.')
                : Column(
                    children: _courses
                        .map(
                          (course) => ListTile(
                            title: Text(course.title),
                            subtitle: LinearProgressIndicator(value: course.progressPercent / 100),
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Gemensam vägg',
            child: _feed.isEmpty
                ? const Text('Inga aktiviteter än.')
                : Column(
                    children: _feed
                        .map(
                          (item) => ListTile(
                            leading: const Icon(Icons.auto_awesome),
                            title: Text(item.summary),
                            subtitle: Text(item.occurredAt?.toIso8601String() ?? ''),
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Tjänster',
            child: _services.isEmpty
                ? const Text('Inga aktiva tjänster just nu.')
                : Column(
                    children: _services
                        .map(
                          (service) => Card(
                            child: ListTile(
                              title: Text(service.title),
                              subtitle: Text('${service.priceCents / 100} ${service.currency.toUpperCase()}'),
                              trailing: FilledButton(
                                onPressed: () => _purchase(service),
                                child: const Text('Köp'),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
