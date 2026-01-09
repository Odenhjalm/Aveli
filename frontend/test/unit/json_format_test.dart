import 'package:flutter_test/flutter_test.dart';
import 'package:aveli/data/models/order.dart';
import 'package:aveli/data/models/service.dart';

void main() {
  group('JSON format (snake_case)', () {
    test('Service model maps snake_case keys', () {
      final json = <String, dynamic>{
        'id': '11111111-1111-4111-8111-111111111111',
        'title': 'Tarotläsning',
        'description': '30 minuter live via Zoom',
        'price_cents': 9500,
        'currency': 'sek',
        'status': 'active',
        'duration_minutes': 30,
        'requires_certification': true,
        'certified_area': 'Tarot',
      };

      final service = Service.fromJson(json);
      expect(service.priceCents, 9500);
      expect(service.requiresCertification, isTrue);
      expect(service.certifiedArea, 'Tarot');

      final encoded = service.toJson();
      expect(encoded, containsPair('price_cents', 9500));
      expect(encoded, containsPair('requires_certification', true));
      expect(encoded, containsPair('certified_area', 'Tarot'));
      expect(
        encoded.keys,
        everyElement(predicate<String>((key) => key == key.toLowerCase())),
      );
    });

    test('Order model maps snake_case keys', () {
      final json = <String, dynamic>{
        'id': '22222222-2222-4222-8222-222222222222',
        'user_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'service_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'course_id': null,
        'amount_cents': 15900,
        'currency': 'sek',
        'status': 'paid',
        'stripe_checkout_id': 'cs_test_123',
        'stripe_payment_intent': 'pi_test_123',
        'metadata': {'foo': 'bar'},
        'created_at': '2024-04-05T12:34:56Z',
        'updated_at': '2024-04-05T12:34:56Z',
      };

      final order = Order.fromJson(json);
      expect(order.amountCents, 15900);
      expect(order.metadata, containsPair('foo', 'bar'));
      expect(
        order.createdAt?.toUtc().toIso8601String(),
        '2024-04-05T12:34:56.000Z',
      );

      final encoded = order.toJson();
      expect(encoded, containsPair('amount_cents', 15900));
      expect(encoded['metadata'], containsPair('foo', 'bar'));
      expect(
        encoded.keys,
        everyElement(predicate<String>((key) => key == key.toLowerCase())),
      );
    });
  });
}
