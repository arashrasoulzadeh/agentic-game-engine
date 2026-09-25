import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'gamepad_controller.dart';

/// Save/load `GamepadController` bindings via `shared_preferences`
/// — mirrors `InputBindingsStorage`'s exact approach for the same
/// reason (cross-platform, no raw `File` I/O). Both button and axis
/// bindings are persisted.
class GamepadBindingsStorage {
  static Future<void> save(
    GamepadController controller, {
    String key = 'engine_gamepad_bindings',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final json = {
      'buttons': {
        for (final entry in controller.buttonBindings.entries)
          entry.key.toString(): entry.value,
      },
      'axes': {
        for (final entry in controller.axisBindings.entries)
          entry.key.toString(): [entry.value.$1, entry.value.$2],
      },
      'axisNames': {
        for (final entry in controller.axisNames.entries)
          entry.key.toString(): entry.value,
      },
    };
    await prefs.setString(key, jsonEncode(json));
  }

  /// Replaces [controller].buttonBindings/axisBindings/axisNames with
  /// whatever was last saved under [key]. Returns `false` with no
  /// effect if nothing was ever saved — the caller keeps whatever
  /// bindings (e.g. `GamepadController.defaultButtonBindings()`) it
  /// already had.
  static Future<bool> load(
    GamepadController controller, {
    String key = 'engine_gamepad_bindings',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return false;

    final json = jsonDecode(raw) as Map<String, dynamic>;
    controller.buttonBindings.clear();

    // Build button bindings
    final buttonBindings = <int, String>{};
    (json['buttons'] as Map<String, dynamic>?)?.forEach((key, value) {
      if (value != null) {
        buttonBindings[int.parse(key)] = value as String;
      }
    });
    controller.buttonBindings.addAll(buttonBindings);

    if (json['axes'] != null) {
      controller.axisBindings.clear();
      final axisBindings = <int, (String, String)>{};
      (json['axes'] as Map<String, dynamic>).forEach((key, value) {
        if (value != null) {
          final List<dynamic> valueList = value as List<dynamic>;
          axisBindings[int.parse(key)] = (valueList[0] as String, valueList[1] as String);
        }
      });
      controller.axisBindings.addAll(axisBindings);
    }

    if (json['axisNames'] != null) {
      controller.axisNames.clear();
      final axisNames = <int, String>{};
      (json['axisNames'] as Map<String, dynamic>).forEach((key, value) {
        if (value != null) {
          axisNames[int.parse(key)] = value as String;
        }
      });
      controller.axisNames.addAll(axisNames);
    }

    return true;
  }

  static const _keyPrefix = 'engine_gamepad_bindings_';

  static String _key(String slot) => '$_keyPrefix$slot';

  /// Save bindings for a specific player slot (for multiplayer).
  static Future<void> saveForPlayer(
    GamepadController controller, {
    int playerIndex = 0,
  }) async {
    await save(controller, key: _key('player$playerIndex'));
  }

  /// Load bindings for a specific player slot.
  static Future<bool> loadForPlayer(
    GamepadController controller, {
    int playerIndex = 0,
  }) async {
    return load(controller, key: _key('player$playerIndex'));
  }

  static Future<bool> hasSave({int playerIndex = 0}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key('player$playerIndex'));
  }

  static Future<void> deleteSave({int playerIndex = 0}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key('player$playerIndex'));
  }
}