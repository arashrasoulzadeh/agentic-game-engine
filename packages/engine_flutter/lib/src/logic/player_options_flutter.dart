import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine_core/engine_core.dart';

/// shared_preferences-backed storage for PlayerOptions.
/// Works on Android, iOS, Web, Windows, macOS, Linux.
class SharedPreferencesPlayerOptionsStorage
    implements PlayerOptionsStorage {
  static const _key = 'player_options';

  final SharedPreferences _prefs;

  SharedPreferencesPlayerOptionsStorage(this._prefs);

  @override
  Future<PlayerOptions?> load() async {
    final jsonString = _prefs.getString(_key);
    if (jsonString == null) return null;
    try {
      return PlayerOptions.fromJson(
          Map<String, dynamic>.from(json.decode(jsonString)));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(PlayerOptions options) async {
    await _prefs.setString(_key, json.encode(options.toJson()));
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}

/// Creates a PlayerOptionsManager with shared_preferences storage.
/// Call this once at app startup (e.g., in main.dart before runApp).
Future<PlayerOptionsManager> createPlayerOptionsManager() async {
  final prefs = await SharedPreferences.getInstance();
  final storage = SharedPreferencesPlayerOptionsStorage(prefs);
  final manager = PlayerOptionsManager(storage);
  await manager.load();
  return manager;
}