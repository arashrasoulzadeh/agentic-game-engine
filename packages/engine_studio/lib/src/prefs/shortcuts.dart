import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

/// Things the studio can do from the keyboard. Each has a default binding that a
/// user can override in `studio_prefs.json`.
enum StudioAction {
  save('Save the open file', 'mod+s'),
  find('Find in file', 'mod+f'),
  replace('Find and replace in file', 'mod+h'),
  searchProject('Search the whole project', 'mod+shift+f');

  const StudioAction(this.label, this.defaultBinding);
  final String label;
  final String defaultBinding;
}

/// Parses a binding such as `mod+shift+f` into the activators that trigger it.
///
/// `mod` is the platform's command key: it yields both the Command and the Control
/// variant, so one default works on macOS and elsewhere. `cmd` and `ctrl` pin one.
/// Returns an empty list for text that is not a binding (unknown modifier or key), so
/// a typo in the prefs file disables that shortcut instead of crashing the studio.
List<SingleActivator> parseBinding(String text) {
  final parts = text.toLowerCase().split('+').map((s) => s.trim()).toList();
  if (parts.length < 2 || parts.any((s) => s.isEmpty)) return const [];
  final key = _keys[parts.last];
  if (key == null) return const [];
  var shift = false, alt = false, cmd = false, ctrl = false, mod = false;
  for (final m in parts.sublist(0, parts.length - 1)) {
    switch (m) {
      case 'shift':
        shift = true;
      case 'alt' || 'option':
        alt = true;
      case 'cmd' || 'meta':
        cmd = true;
      case 'ctrl' || 'control':
        ctrl = true;
      case 'mod':
        mod = true;
      default:
        return const [];
    }
  }
  if (!mod && !cmd && !ctrl && !alt) return const [];
  SingleActivator make({required bool c, required bool m}) =>
      SingleActivator(key, shift: shift, alt: alt, control: c, meta: m);
  if (mod) {
    return [make(c: false, m: true), make(c: true, m: false)];
  }
  return [make(c: ctrl, m: cmd)];
}

final Map<String, LogicalKeyboardKey> _keys = {
  for (var c = 'a'.codeUnitAt(0); c <= 'z'.codeUnitAt(0); c++)
    String.fromCharCode(c): LogicalKeyboardKey.findKeyByKeyId(
      LogicalKeyboardKey.keyA.keyId + (c - 'a'.codeUnitAt(0)),
    )!,
  for (var d = 0; d <= 9; d++)
    '$d': LogicalKeyboardKey.findKeyByKeyId(
      LogicalKeyboardKey.digit0.keyId + d,
    )!,
};

/// The studio's active keyboard bindings: defaults with the user's overrides on top.
class ShortcutMap {
  ShortcutMap([Map<StudioAction, String> overrides = const {}])
    : _overrides = Map.of(overrides);

  /// What screens read. Set once at startup from the prefs file.
  static ShortcutMap current = ShortcutMap();

  final Map<StudioAction, String> _overrides;

  /// The binding text for [action], as written (for showing in a menu).
  String bindingFor(StudioAction action) =>
      _overrides[action] ?? action.defaultBinding;

  /// The activators for [action]; empty if its binding text is invalid.
  List<SingleActivator> activatorsFor(StudioAction action) =>
      parseBinding(bindingFor(action));

  /// [CallbackShortcuts] bindings for the actions in [handlers].
  Map<ShortcutActivator, VoidCallback> bindings(
    Map<StudioAction, VoidCallback> handlers,
  ) => {
    for (final e in handlers.entries)
      for (final a in activatorsFor(e.key)) a: e.value,
  };

  /// Pairs of actions whose bindings can fire on the same keys. A conflict makes one
  /// of them unreachable, so the prefs screen and loader surface them.
  List<(StudioAction, StudioAction)> conflicts() {
    final out = <(StudioAction, StudioAction)>[];
    final all = StudioAction.values;
    for (var i = 0; i < all.length; i++) {
      for (var j = i + 1; j < all.length; j++) {
        final a = activatorsFor(all[i]), b = activatorsFor(all[j]);
        final clash = a.any(
          (x) => b.any(
            (y) =>
                x.trigger == y.trigger &&
                x.shift == y.shift &&
                x.alt == y.alt &&
                x.control == y.control &&
                x.meta == y.meta,
          ),
        );
        if (clash) out.add((all[i], all[j]));
      }
    }
    return out;
  }

  /// Reads the `shortcuts` object of a prefs document. Unknown actions are ignored
  /// (a newer studio's prefs file still loads in an older one).
  factory ShortcutMap.fromJson(Map<String, dynamic> json) {
    final raw = json['shortcuts'];
    final overrides = <StudioAction, String>{};
    if (raw is Map) {
      for (final action in StudioAction.values) {
        final v = raw[action.name];
        if (v is String) overrides[action] = v;
      }
    }
    return ShortcutMap(overrides);
  }

  Map<String, dynamic> toJson() => {
    'shortcuts': {for (final e in _overrides.entries) e.key.name: e.value},
  };
}

/// Where the studio keeps per-user settings: outside any project, so they follow the
/// person and never land in a game's repository.
File studioPrefsFile({Map<String, String>? env}) {
  final e = env ?? Platform.environment;
  final home = e['HOME'] ?? e['USERPROFILE'] ?? '.';
  return File(p.join(home, '.game_agent', 'studio_prefs.json'));
}

/// Loads the shortcut map from [file]. A missing or unreadable file gives the defaults
/// - a broken prefs file must never keep the studio from starting.
ShortcutMap loadShortcuts(File file) {
  try {
    if (!file.existsSync()) return ShortcutMap();
    final json = jsonDecode(file.readAsStringSync());
    return json is Map<String, dynamic>
        ? ShortcutMap.fromJson(json)
        : ShortcutMap();
  } on Object {
    return ShortcutMap();
  }
}

/// Writes [map] to [file], creating its folder.
void saveShortcuts(File file, ShortcutMap map) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(map.toJson()),
  );
}
