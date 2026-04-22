import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'lesson_markdown_roundtrip.dart' as roundtrip;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lesson markdown roundtrip harness', () async {
    final inputPath = Platform.environment['LESSON_MARKDOWN_INPUT_PATH'];
    final outputPath = Platform.environment['LESSON_MARKDOWN_OUTPUT_PATH'];

    if (inputPath == null || inputPath.isEmpty) {
      fail('Missing LESSON_MARKDOWN_INPUT_PATH');
    }
    if (outputPath == null || outputPath.isEmpty) {
      fail('Missing LESSON_MARKDOWN_OUTPUT_PATH');
    }

    final inputFile = File(inputPath);
    final outputFile = File(outputPath);
    final payload = await inputFile.readAsString();
    final result = roundtrip.roundTripLessonMarkdownPayload(payload);
    final decoded = jsonDecode(result);

    expect(decoded, isA<Map<String, dynamic>>());
    await outputFile.writeAsString(result);
  });
}
