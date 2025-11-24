import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('does not bundle foundations audio asset', () async {
    expect(
      () async => rootBundle.load(
        'assets/audio/foundations_of_soulwisdom/'
        'anglar_ovning_rensa_och_rena_ditt_energifalt.wav',
      ),
      throwsA(isA<FlutterError>()),
    );
  });
}
