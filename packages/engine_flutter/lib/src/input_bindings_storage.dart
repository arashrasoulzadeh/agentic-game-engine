import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'input.dart';

/// Save/load `InputController.bindings` via `shared_preferences` — the
/// persistence half of "press a key to rebind" (see `RemapMenuScene`
/// for the UI half), so a remap survives an app restart. Mirrors
/// `SaveGame`'s cross-platform choice: `shared_preferences` works
/// identically on Android/iOS/web/desktop, unlike raw `File` I/O
/// (`path_provider`'s `File` APIs don't exist on web at all).
class InputBindingsStorage {
  /// Serializes [controller]'s current `bindings` (each
  /// `LogicalKeyboardKey.keyId` + its bound action name) under [key].
  static Future<void> save(
    InputController controller, {
    String key = 'engine_input_bindings',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final json = {
      for (final entry in controller.bindings.entries) entry.key.keyId.toString(): entry.value,
    };
    await prefs.setString(key, jsonEncode(json));
  }

  /// Replaces [controller].bindings with whatever was last saved under
  /// [key]. Returns `false` with no effect if nothing was ever saved —
  /// the caller keeps whatever bindings (e.g.
  /// `InputController.defaultBindings()`) it already had.
  static Future<bool> load(
    InputController controller, {
    String key = 'engine_input_bindings',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return false;

    final json = jsonDecode(raw) as Map<String, dynamic>;
    controller.bindings
      ..clear()
      ..addAll({
        for (final entry in json.entries)
          LogicalKeyboardKey(int.parse(entry.key)): entry.value as String,
      });
    return true;
  }
}
