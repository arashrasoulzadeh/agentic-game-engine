import 'session.dart';

/// Off the web there is no browser storage; this keeps the save in memory under [key] so the same game
/// code runs in tests and on desktop (where [FileSaveStore] is the real choice).
class BrowserSaveStore implements SaveStore {
  BrowserSaveStore([this.key = 'idle_save']);

  final String key;
  static final Map<String, Map<String, dynamic>> _memory = {};

  @override
  Map<String, dynamic>? read() => _memory[key];

  @override
  void write(Map<String, dynamic> save) => _memory[key] = save;
}
