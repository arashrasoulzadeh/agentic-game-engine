import 'dart:io';

import 'package:path/path.dart' as p;

/// File access for operations, so they run against a real project or an in-memory one in tests. Paths are
/// absolute and already sandboxed by `ProjectRoot`.
abstract class ProjectFiles {
  String? read(String path);
  bool exists(String path);

  /// Absolute paths of files directly in [dir] (or below it when [recursive]), sorted.
  List<String> list(String dir, {bool recursive = false});

  /// Writes [content] completely or not at all (temp file + rename).
  void writeAtomic(String path, String content);
  void delete(String path);
}

/// The real file system.
class DiskFiles implements ProjectFiles {
  const DiskFiles();

  @override
  String? read(String path) {
    final f = File(path);
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  @override
  bool exists(String path) => File(path).existsSync();

  @override
  List<String> list(String dir, {bool recursive = false}) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    return [
      for (final e in d.listSync(recursive: recursive, followLinks: false))
        if (e is File) e.path,
    ]..sort();
  }

  @override
  void writeAtomic(String path, String content) {
    final target = File(path);
    target.parent.createSync(recursive: true);
    final temp = File('$path.tmp-${DateTime.now().microsecondsSinceEpoch}');
    temp.writeAsStringSync(content, flush: true);
    temp.renameSync(path);
  }

  @override
  void delete(String path) {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }
}

/// A file system in memory, for tests.
class MemoryFiles implements ProjectFiles {
  MemoryFiles([Map<String, String>? initial]) : files = {...?initial};

  final Map<String, String> files;

  /// Make the next [writeAtomic] to this path fail, to test partial-write handling.
  final Set<String> failWrites = {};

  @override
  String? read(String path) => files[p.normalize(path)] ?? files[path];

  @override
  bool exists(String path) =>
      files.containsKey(p.normalize(path)) || files.containsKey(path);

  @override
  List<String> list(String dir, {bool recursive = false}) {
    final prefix = p.normalize(dir);
    return [
      for (final k in files.keys)
        if (p.dirname(k) == prefix || (recursive && p.isWithin(prefix, k))) k,
    ]..sort();
  }

  @override
  void writeAtomic(String path, String content) {
    if (failWrites.contains(path))
      throw FileSystemException('simulated failure', path);
    files[p.normalize(path)] = content;
  }

  @override
  void delete(String path) => files.remove(p.normalize(path));
}
