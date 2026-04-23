import 'dart:convert';
import 'dart:io';

import 'package:aveli/editor/document/lesson_document.dart';

const lessonDocumentFixtureCorpusPath =
    'actual_truth/contracts/lesson_document_fixture_corpus.json';

LessonDocumentFixtureCorpus loadLessonDocumentFixtureCorpus() {
  final file = _findCorpusFile();
  return LessonDocumentFixtureCorpus.fromJson(
    _objectMap(jsonDecode(file.readAsStringSync())),
  );
}

final class LessonDocumentFixtureCorpus {
  const LessonDocumentFixtureCorpus({
    required this.raw,
    required this.mediaRows,
    required this.requiredCapabilities,
    required this.capabilityCoverage,
    required this.fixtures,
  });

  final Map<String, Object?> raw;
  final List<LessonDocumentCorpusMedia> mediaRows;
  final List<String> requiredCapabilities;
  final Map<String, List<String>> capabilityCoverage;
  final Map<String, Map<String, Object?>> fixtures;

  Map<String, String> get mediaTypesByLessonMediaId => {
    for (final row in mediaRows) row.lessonMediaId: row.mediaType,
  };

  List<String> fixtureIdsForCapability(String capability) {
    return capabilityCoverage[capability] ?? const <String>[];
  }

  Map<String, Object?> fixture(String fixtureId) {
    final fixture = fixtures[fixtureId];
    if (fixture == null) {
      throw StateError('Missing lesson document fixture: $fixtureId');
    }
    return fixture;
  }

  LessonDocument document(String fixtureId, {String field = 'document'}) {
    return LessonDocument.fromJson(
      documentJson(fixtureId, field: field),
      mediaTypesByLessonMediaId: mediaTypesByLessonMediaId,
    );
  }

  Map<String, Object?> documentJson(
    String fixtureId, {
    String field = 'document',
  }) {
    final payload = fixture(fixtureId)[field];
    if (payload is! Map) {
      throw StateError('$fixtureId.$field is not a document object');
    }
    return _objectMap(payload);
  }

  LessonDocumentClearFormattingFixture clearFormattingFixture(
    String fixtureId,
  ) {
    final payload = fixture(fixtureId);
    return LessonDocumentClearFormattingFixture(
      source: document(fixtureId),
      expected: document(fixtureId, field: 'expected_document'),
      operation: _objectMap(payload['operation']),
    );
  }

  Iterable<(String fixtureId, String field)> documentFields() sync* {
    const fields = {
      'document',
      'expected_document',
      'saved_document',
      'draft_document',
      'initial_document',
      'updated_document',
      'stale_attempt_document',
    };
    for (final entry in fixtures.entries) {
      for (final field in fields) {
        if (entry.value.containsKey(field)) {
          yield (entry.key, field);
        }
      }
    }
  }

  static LessonDocumentFixtureCorpus fromJson(Map<String, Object?> payload) {
    final mediaRows = _list(payload['media_rows'])
        .map((item) => LessonDocumentCorpusMedia.fromJson(_objectMap(item)))
        .toList(growable: false);

    return LessonDocumentFixtureCorpus(
      raw: payload,
      mediaRows: mediaRows,
      requiredCapabilities: _list(
        payload['required_capabilities'],
      ).cast<String>().toList(growable: false),
      capabilityCoverage: _stringListMap(payload['capability_coverage']),
      fixtures: {
        for (final entry in _objectMap(payload['fixtures']).entries)
          entry.key: _objectMap(entry.value),
      },
    );
  }
}

final class LessonDocumentCorpusMedia {
  const LessonDocumentCorpusMedia({
    required this.lessonMediaId,
    required this.mediaAssetId,
    required this.mediaType,
    required this.state,
    required this.label,
    required this.resolvedUrl,
  });

  final String lessonMediaId;
  final String mediaAssetId;
  final String mediaType;
  final String state;
  final String label;
  final String resolvedUrl;

  static LessonDocumentCorpusMedia fromJson(Map<String, Object?> payload) {
    return LessonDocumentCorpusMedia(
      lessonMediaId: _string(payload['lesson_media_id']),
      mediaAssetId: _string(payload['media_asset_id']),
      mediaType: _string(payload['media_type']),
      state: _string(payload['state']),
      label: _string(payload['label']),
      resolvedUrl: _string(payload['resolved_url']),
    );
  }
}

final class LessonDocumentClearFormattingFixture {
  const LessonDocumentClearFormattingFixture({
    required this.source,
    required this.expected,
    required this.operation,
  });

  final LessonDocument source;
  final LessonDocument expected;
  final Map<String, Object?> operation;

  int get blockIndex => operation['block_index'] as int;
  int get start => operation['start'] as int;
  int get end => operation['end'] as int;
}

File _findCorpusFile() {
  final candidates = [
    File(lessonDocumentFixtureCorpusPath),
    File('../$lessonDocumentFixtureCorpusPath'),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      return candidate;
    }
  }
  throw StateError(
    'Unable to locate $lessonDocumentFixtureCorpusPath from ${Directory.current.path}',
  );
}

Map<String, List<String>> _stringListMap(Object? value) {
  return {
    for (final entry in _objectMap(value).entries)
      entry.key: _list(entry.value).cast<String>().toList(growable: false),
  };
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    throw StateError('Expected object, found ${value.runtimeType}');
  }
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value) {
  if (value is! List) {
    throw StateError('Expected list, found ${value.runtimeType}');
  }
  return value.cast<Object?>();
}

String _string(Object? value) {
  if (value is! String) {
    throw StateError('Expected string, found ${value.runtimeType}');
  }
  return value;
}
