import 'dart:io';

import 'package:path/path.dart' as p;

import 'result.dart';

/// An open project folder and the one safe way to turn a project-relative path into a file path.
///
/// Every `path` parameter of every operation goes through [resolve], which refuses absolute paths, `..`, NUL
/// bytes and symlinks that leave the project, so no operation can touch anything outside the folder.
class ProjectRoot {
  ProjectRoot(String root) : root = _canonical(root);

  /// Absolute, symlink-resolved project folder.
  final String root;

  static String _canonical(String path) {
    final dir = Directory(path);
    return dir.existsSync()
        ? dir.resolveSymbolicLinksSync()
        : p.normalize(p.absolute(path));
  }

  /// The absolute path of [relative] inside the project. Throws [OpError] (`invalid_params`) if it would escape.
  String resolve(String relative) {
    if (relative.isEmpty || relative.contains('\u0000')) {
      throw OpError(
        ErrorCode.invalidParams,
        'The path is empty or contains a NUL byte.',
      );
    }
    final unified = relative.replaceAll('\\', '/');
    if (p.isAbsolute(unified) || RegExp(r'^[A-Za-z]:').hasMatch(unified)) {
      throw OpError(
        ErrorCode.invalidParams,
        'Paths must be relative to the project ("$relative").',
        hint: 'Use a project-relative path such as assets/levels/level1.json.',
      );
    }
    if (p.split(p.normalize(unified)).contains('..')) {
      throw OpError(
        ErrorCode.invalidParams,
        'The path leaves the project ("$relative").',
      );
    }
    final joined = p.normalize(p.join(root, unified));
    if (!p.isWithin(root, joined) && joined != root) {
      throw OpError(
        ErrorCode.invalidParams,
        'The path leaves the project ("$relative").',
      );
    }
    // Resolve symlinks on the deepest existing ancestor so a link inside the project cannot lead outside it.
    var probe = joined;
    while (!FileSystemEntity.isLinkSync(probe) &&
        !File(probe).existsSync() &&
        !Directory(probe).existsSync() &&
        probe != root &&
        p.dirname(probe) != probe) {
      probe = p.dirname(probe);
    }
    if (File(probe).existsSync() ||
        Directory(probe).existsSync() ||
        FileSystemEntity.isLinkSync(probe)) {
      final real = FileSystemEntity.isDirectorySync(probe)
          ? Directory(probe).resolveSymbolicLinksSync()
          : File(probe).resolveSymbolicLinksSync();
      if (real != root && !p.isWithin(root, real)) {
        throw OpError(
          ErrorCode.invalidParams,
          'The path leaves the project through a link ("$relative").',
        );
      }
    }
    return joined;
  }

  /// [absolute] relative to the project, with forward slashes.
  String relativeOf(String absolute) =>
      p.relative(absolute, from: root).replaceAll('\\', '/');
}
