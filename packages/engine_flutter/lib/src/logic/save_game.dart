import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown by [SaveGame.load] when a save's schema version doesn't match
/// the version the game is currently running, and no `migrate` callback
/// was given to reconcile the difference. A save shape drifting out
/// from under an old save file is expected over a game's lifetime (a
/// new required component field, a renamed key) — this makes that a
/// clear, catchable failure instead of a confusing
/// `ComponentApplyException` from deep inside `Level.loadInto`, or
/// (worse) a silent bug from stale data quietly loading wrong.
class SaveVersionException implements Exception {
  final int savedVersion;
  final int currentVersion;
  SaveVersionException(this.savedVersion, this.currentVersion);

  @override
  String toString() =>
      'SaveVersionException: save data is at schema version $savedVersion '
      'but the game is at version $currentVersion. Pass a `migrate` '
      'callback to SaveGame.load to upgrade old saves, or bump `version` '
      'to match if the save shape didn\'t actually change.';
}

/// Save/load a `World` snapshot via `shared_preferences` — chosen over
/// raw file I/O because it works identically on Android, iOS, web, and
/// desktop; `dart:io`'s `File` APIs don't exist on web at all, which
/// this engine explicitly targets.
///
/// Serializes through `World.toJson()`/`applyPatch()`, the same
/// snapshot/patch machinery the agent-facing API already uses — saving
/// a game and an agent reading/writing world state are the same
/// underlying operation.
class SaveGame {
  /// Serializes [world] and stores it under [slot], tagged with
  /// [version] — bump this whenever a save-affecting shape changes (a
  /// new required component field, a renamed key) so [load] can tell a
  /// stale save apart from a current one instead of guessing. Defaults
  /// to `1`, the implicit version of every save written before this
  /// parameter existed. Multiple slots let a game support more than one
  /// save file.
  static Future<void> save(World world, {String slot = 'default', int version = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final envelope = {'schemaVersion': version, 'world': world.toJson()};
    await prefs.setString(_key(slot), jsonEncode(envelope));
  }

  /// Spawns fresh entities on [world] from the saved snapshot for
  /// [slot], via `Level.loadInto` — deliberately not `World.applyPatch`,
  /// which only patches entity ids that already exist in the target
  /// world and would silently restore nothing into a freshly constructed
  /// one. Call this on a new `World` (components registered, nothing
  /// spawned yet), not one `populateWorld` has already filled in.
  /// Returns `false` with no effect if no save exists for that slot.
  ///
  /// If the save's stored schema version doesn't match [version],
  /// [migrate] is called with the raw saved world JSON and the version
  /// it was saved at, and must return world JSON shaped for the
  /// *current* version — typically by patching/renaming whatever
  /// changed since. With no [migrate] given, a version mismatch throws
  /// [SaveVersionException] rather than attempting to load
  /// (potentially wrong-shaped) data anyway. A save written before
  /// `version` existed on [save] is treated as version `1`.
  ///
  /// Throws [LevelLoadException] if the stored data isn't a JSON object
  /// at all (corrupted storage, or a save written by something else
  /// entirely) — `Level.loadInto` itself already throws that same
  /// exception type for a malformed-but-object-shaped snapshot, so a
  /// caller catching it handles both cases the same way.
  static Future<bool> load(
    World world, {
    String slot = 'default',
    int version = 1,
    Map<String, dynamic> Function(Map<String, dynamic> savedWorldJson, int savedVersion)? migrate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(slot));
    if (raw == null) return false;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw LevelLoadException(
        'Save data for slot "$slot" is corrupted: expected a JSON '
        'object, got ${decoded.runtimeType}',
      );
    }

    // A save written by a pre-versioning `save()` has no envelope --
    // the whole decoded map *is* the World JSON (which never itself
    // has a "world" key), so its implicit version is 1.
    final hasEnvelope = decoded['world'] is Map<String, dynamic>;
    final savedVersion = hasEnvelope ? (decoded['schemaVersion'] as num?)?.toInt() ?? 1 : 1;
    var worldJson = hasEnvelope ? decoded['world'] as Map<String, dynamic> : decoded;

    if (savedVersion != version) {
      if (migrate == null) {
        throw SaveVersionException(savedVersion, version);
      }
      worldJson = migrate(worldJson, savedVersion);
    }

    Level.loadInto(world, worldJson);
    return true;
  }

  static Future<bool> hasSave({String slot = 'default'}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key(slot));
  }

  static Future<void> deleteSave({String slot = 'default'}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(slot));
  }

  /// Every slot with a save currently stored, for a save-slot picker UI
  /// (`SaveSlotMenuScene`) to list without the caller having to already
  /// know every slot name up front — `shared_preferences` keys aren't
  /// namespaced by prefix on their own, so this filters to just the ones
  /// [save]/[load] use and strips the `_keyPrefix` back off.
  static Future<List<String>> listSlots() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs
        .getKeys()
        .where((key) => key.startsWith(_keyPrefix))
        .map((key) => key.substring(_keyPrefix.length))
        .toList();
  }

  static const _keyPrefix = 'engine_save_';

  static String _key(String slot) => '$_keyPrefix$slot';
}
