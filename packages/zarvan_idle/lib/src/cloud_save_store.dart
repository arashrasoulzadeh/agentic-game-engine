import 'dart:async';



/// A save kept on a server (Game Center, Play Games, your own backend). The engine defines only the
/// contract; each platform's implementation belongs to the game.
abstract class CloudSaveStore {
  /// The saved game in the cloud, or null if there is none.
  Future<Map<String, dynamic>?> fetch();

  /// Replaces the cloud copy with [save].
  Future<void> push(Map<String, dynamic> save);
}

/// A [CloudSaveStore] in memory, for tests.
class MemoryCloudSaveStore implements CloudSaveStore {
  Map<String, dynamic>? value;
  int pushes = 0;

  @override
  Future<Map<String, dynamic>?> fetch() async => value;

  @override
  Future<void> push(Map<String, dynamic> save) async {
    value = save;
    pushes++;
  }
}

/// What [IdleSession.syncCloud] did.
enum CloudSyncResult {
  /// Both sides were empty, or already the same moment.
  unchanged,

  /// The local game replaced the cloud copy.
  pushed,

  /// The cloud copy replaced the local game.
  pulled,
}
