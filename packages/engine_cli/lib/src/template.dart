import 'dart:io';

/// Locates a bundled template directory regardless of whether this CLI is
/// running from source (`dart run bin/game_agent.dart`) or from a global
/// activation (`dart pub global activate --source git ...`) — in both
/// cases `Platform.script` points at this package's own `bin/` file, so
/// walking up two directories reaches the package root.
Directory templateRoot(String templateName) {
  final scriptFile = File(Platform.script.toFilePath());
  final packageRoot = scriptFile.parent.parent;
  final dir = Directory('${packageRoot.path}/templates/$templateName');
  if (!dir.existsSync()) {
    throw StateError(
      'Template "$templateName" not found at ${dir.path}. '
      'Expected packages/engine_cli/templates/$templateName to exist.',
    );
  }
  return dir;
}

/// Copies every file under [source] into [destination], applying
/// [replacements] to file contents and stripping a trailing `.tmpl` from
/// filenames. Directory structure is preserved.
void copyTemplate(
  Directory source,
  Directory destination,
  Map<String, String> replacements,
) {
  for (final entity in source.listSync(recursive: true)) {
    final relative = entity.path.substring(source.path.length + 1);
    if (entity is Directory) {
      Directory('${destination.path}/$relative').createSync(recursive: true);
      continue;
    }
    if (entity is! File) continue;

    var targetRelative = relative;
    if (targetRelative.endsWith('.tmpl')) {
      targetRelative = targetRelative.substring(0, targetRelative.length - 5);
    }
    final targetFile = File('${destination.path}/$targetRelative');
    targetFile.parent.createSync(recursive: true);

    var content = entity.readAsStringSync();
    replacements.forEach((key, value) {
      content = content.replaceAll('{{$key}}', value);
    });
    targetFile.writeAsStringSync(content);
  }
}
