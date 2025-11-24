import 'dart:io';

const audioRoot = 'backend/assets/audio';

Future<void> main() async {
  final audioDir = Directory(audioRoot);
  if (!audioDir.existsSync()) {
    stderr.writeln('Directory $audioRoot not found.');
    exit(1);
  }

  final courseDirs =
      await audioDir
            .list()
            .where((entity) => entity is Directory)
            .cast<Directory>()
            .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final dir in courseDirs) {
    await _ensureGitkeep(dir);
  }

  stdout.writeln(
    'Verified ${courseDirs.length} course audio directories under $audioRoot.',
  );
}

Future<void> _ensureGitkeep(Directory dir) async {
  final gitkeep = File('${dir.path}/.gitkeep');
  if (await gitkeep.exists()) return;
  await gitkeep.writeAsString('');
}
