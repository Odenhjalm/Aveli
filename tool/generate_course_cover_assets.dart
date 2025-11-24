import 'dart:io';

const sourceDir = 'backend/assets/images/courses';
const outputFile = 'lib/shared/utils/course_cover_assets.g.dart';

String _slugFromFileName(String name) {
  final base = name.contains('.')
      ? name.substring(0, name.lastIndexOf('.'))
      : name;
  return base
      .replaceAll(RegExp(r'[_\s]+'), '-')
      .replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '')
      .toLowerCase();
}

Future<void> main() async {
  final dir = Directory(sourceDir);
  if (!await dir.exists()) {
    stderr.writeln('Directory $sourceDir not found.');
    exit(1);
  }

  final files =
      await dir.list().where((entity) => entity is File).cast<File>().where((
          file,
        ) {
          final lower = file.path.toLowerCase();
          return lower.endsWith('.png') ||
              lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.webp');
        }).toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final entries = <String, String>{};

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final slug = _slugFromFileName(name);
    if (slug.isEmpty) {
      stdout.writeln('Skipping $name (could not derive slug).');
      continue;
    }
    final relativePath = 'images/courses/$name';
    entries[slug] = relativePath;
  }

  final buffer = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln(
      '// Run `dart run tool/generate_course_cover_assets.dart` to regenerate.',
    )
    ..writeln()
    ..writeln('const Map<String, String> courseCoverAssets = {');

  final sortedKeys = entries.keys.toList()..sort();
  for (final key in sortedKeys) {
    final path = entries[key]!;
    buffer.writeln("  '$key': '$path',");
  }

  buffer.writeln('};');

  await File(outputFile).writeAsString(buffer.toString());
  stdout.writeln(
    'Generated ${entries.length} course cover mappings to $outputFile',
  );
}
