import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Reads the git commit `zarvan_core` was resolved to out of a pubspec.lock.
///
/// Returns the first 7 characters of `resolved-ref`, or null when the lock
/// has no git-sourced `zarvan_core` (a `path:` dependency has no commit).
String? engineCommitFromLock(String lockText) {
  final lock = loadYaml(lockText);
  final packages = lock is YamlMap ? lock['packages'] : null;
  final core = packages is YamlMap ? packages['zarvan_core'] : null;
  final description = core is YamlMap ? core['description'] : null;
  final ref = description is YamlMap ? description['resolved-ref'] : null;
  return ref is String && ref.length >= 7 ? ref.substring(0, 7) : null;
}

/// Runs `git describe --tags --always --dirty` in a directory; null on failure.
typedef GitDescribe = String? Function(String directory);

String? _gitDescribe(String directory) {
  try {
    final r = Process.runSync('git', [
      'describe',
      '--tags',
      '--always',
      '--dirty',
    ], workingDirectory: directory);
    final out = (r.stdout as String).trim();
    return r.exitCode == 0 && out.isNotEmpty ? out : null;
  } on ProcessException {
    return null;
  }
}

/// The engine commit a game in [projectDir] is built against, for the splash.
///
/// A git dependency answers from `pubspec.lock`; a local `path:` dependency
/// (monorepo development) answers with `git describe` of the engine checkout.
/// Null when neither can tell, in which case the splash shows `dev`.
String? resolveEngineCommit(
  String projectDir, {
  GitDescribe describe = _gitDescribe,
}) {
  final lock = File(p.join(projectDir, 'pubspec.lock'));
  if (lock.existsSync()) {
    final fromLock = engineCommitFromLock(lock.readAsStringSync());
    if (fromLock != null) return fromLock;
    final path = _pathOfCore(loadYaml(lock.readAsStringSync()), projectDir);
    if (path != null) return describe(path);
  }
  return null;
}

String? _pathOfCore(Object? lock, String projectDir) {
  final packages = lock is YamlMap ? lock['packages'] : null;
  final core = packages is YamlMap ? packages['zarvan_core'] : null;
  final description = core is YamlMap ? core['description'] : null;
  final path = description is YamlMap ? description['path'] : null;
  if (path is! String) return null;
  return p.normalize(p.isAbsolute(path) ? path : p.join(projectDir, path));
}
