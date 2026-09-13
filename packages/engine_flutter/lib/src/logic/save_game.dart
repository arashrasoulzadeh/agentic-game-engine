import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  /// Serializes [world] and stores it under [slot]. Multiple slots let a
  /// game support more than one save file.
  static Future<void> save(World world, {String slot = 'default'}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(slot), jsonEncode(world.toJson()));
  }

  /// Spawns fresh entities on [world] from the saved snapshot for
  /// [slot], via `Level.loadInto` — deliberately not `World.applyPatch`,
  /// which only patches entity ids that already exist in the target
  /// world and would silently restore nothing into a freshly constructed
  /// one. Call this on a new `World` (components registered, nothing
  /// spawned yet), not one `populateWorld` has already filled in.
  /// Returns `false` with no effect if no save exists for that slot.
  static Future<bool> load(World world, {String slot = 'default'}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(slot));
    if (raw == null) return false;
    Level.loadInto(world, jsonDecode(raw) as Map<String, dynamic>);
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

  static String _key(String slot) => 'engine_save_$slot';
}
