import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'gamepad_controller.dart';

/// Save/load `GamepadController.buttonBindings` via `shared_preferences`
/// — mirrors `InputBindingsStorage`'s exact approach for the same
/// reason (cross-platform, no raw `File` I/O). Only button bindings are
/// persisted, not axis bindings/names/deadzone — those describe a
/// physical stick's shape (which axis id is "horizontal") rather than a
/// player preference, so remapping UI is expected to only ever offer
/// buttons to rebind, the same way a real console's "customize
/// controls" screen does.
class GamepadBindingsStorage {
  static Future<void> save(
    GamepadController controller, {
    String key = 'engine_gamepad_bindings',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final json = {
      for (final entry in controller.buttonBindings.entries)
        entry.key.toString(): entry.value,
    };
    await prefs.setString(key, jsonEncode(json));
  }

  /// Replaces [controller].buttonBindings with whatever was last saved
  /// under [key]. Returns `false` with no effect if nothing was ever
  /// saved — the caller keeps whatever bindings (e.g.
  /// `GamepadController.defaultButtonBindings()`) it already had.
  static Future<bool> load(
    GamepadController controller, {
    String key = 'engine_gamepad_bindings',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return false;

    final json = jsonDecode(raw) as Map<String, dynamic>;
    controller.buttonBindings
      ..clear()
      ..addAll({
        for (final entry in json.entries) int.parse(entry.key): entry.value as String,
      });
    return true;
  }
}
