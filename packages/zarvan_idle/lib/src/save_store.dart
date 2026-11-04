import 'package:zarvan_core/zarvan_core_io.dart' show AtomicSave;

/// Where a game keeps its save. An interface so tests (and web, where there is no file system) can
/// supply their own.
abstract class SaveStore {
  /// The newest readable save, or null.
  Map<String, dynamic>? read();

  /// Stores [save], replacing the previous one.
  void write(Map<String, dynamic> save);
}

/// A [SaveStore] in memory, for tests.
class MemorySaveStore implements SaveStore {
  Map<String, dynamic>? value;

  @override
  Map<String, dynamic>? read() => value;

  @override
  void write(Map<String, dynamic> save) => value = save;
}

/// A [SaveStore] on disk using `AtomicSave`: a crash mid-write leaves the previous save, and a corrupt
/// file falls back to the backup.
class FileSaveStore implements SaveStore {
  FileSaveStore(String path) : _file = AtomicSave(path);
  final AtomicSave _file;

  @override
  Map<String, dynamic>? read() => _file.read();

  @override
  void write(Map<String, dynamic> save) => _file.write(save);
}
