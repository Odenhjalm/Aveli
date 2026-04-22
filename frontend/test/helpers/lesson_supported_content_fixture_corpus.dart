import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

const String _fixtureCorpusRelativePath =
    'actual_truth/contracts/lesson_supported_content_fixture_corpus.json';

Directory _repoRootDirectory() {
  var current = Directory.current.absolute;
  while (true) {
    final candidate = File(
      '${current.path}${Platform.pathSeparator}${_fixtureCorpusRelativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    if (candidate.existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'Could not locate $_fixtureCorpusRelativePath from ${Directory.current.path}.',
      );
    }
    current = parent;
  }
}

File lessonSupportedContentFixtureCorpusFile() {
  final root = _repoRootDirectory();
  return File(
    '${root.path}${Platform.pathSeparator}${_fixtureCorpusRelativePath.replaceAll('/', Platform.pathSeparator)}',
  );
}

File repoRelativeFile(String relativePath) {
  final root = _repoRootDirectory();
  return File(
    '${root.path}${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}',
  );
}

JsonMap loadLessonSupportedContentFixtureCorpus() {
  final raw = jsonDecode(
    lessonSupportedContentFixtureCorpusFile().readAsStringSync(),
  );
  if (raw is! Map) {
    throw StateError('Fixture corpus must decode to a JSON object.');
  }
  return Map<String, dynamic>.from(raw);
}

JsonMap _mapField(JsonMap source, String fieldName) {
  final raw = source[fieldName];
  if (raw is! Map) {
    throw StateError(
      'Fixture corpus field "$fieldName" must be a JSON object.',
    );
  }
  return Map<String, dynamic>.from(raw);
}

JsonMap bindingGroup(JsonMap corpus, String id) {
  final groups = _mapField(corpus, 'binding_groups');
  final raw = groups[id];
  if (raw is! Map) {
    throw StateError('Missing binding group "$id".');
  }
  return Map<String, dynamic>.from(raw);
}

JsonMap supportedCanonicalFixture(JsonMap corpus, String id) {
  final fixtures = _mapField(corpus, 'supported_canonical_fixtures');
  final raw = fixtures[id];
  if (raw is! Map) {
    throw StateError('Missing supported fixture "$id".');
  }
  return Map<String, dynamic>.from(raw);
}

List<String> stringListField(JsonMap source, String fieldName) {
  final raw = source[fieldName];
  if (raw is! List) {
    throw StateError('Fixture corpus field "$fieldName" must be a JSON list.');
  }
  return raw.map((value) => '$value').toList(growable: false);
}
