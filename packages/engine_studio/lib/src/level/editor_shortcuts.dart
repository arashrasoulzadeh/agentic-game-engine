import 'package:flutter/services.dart';

import 'level_editor.dart';

/// What a keyboard shortcut does in the level editor. The mapping from keys is
/// kept apart from the screen, so the table is testable and the screen only
/// runs the actions.
enum EditorAction { undo, redo, save, deleteSelected, toggleGrid, tool }

/// The action a key press triggers, with the tool it selects for [EditorAction.tool].
class ShortcutResult {
  final EditorAction action;
  final EditorTool? tool;

  const ShortcutResult(this.action, [this.tool]);
}

/// Maps a key press to an editor action, or null when the key does nothing here.
///
/// Tool keys are bare letters, which is why the screen ignores them while a text
/// field has focus; the mapping itself does not know about focus. [command] is
/// Cmd on macOS and Ctrl elsewhere.
ShortcutResult? shortcutFor(
  LogicalKeyboardKey key, {
  required bool command,
  required bool shift,
}) {
  if (command) {
    if (key == LogicalKeyboardKey.keyZ) {
      return ShortcutResult(shift ? EditorAction.redo : EditorAction.undo);
    }
    if (key == LogicalKeyboardKey.keyY) {
      return const ShortcutResult(EditorAction.redo);
    }
    if (key == LogicalKeyboardKey.keyS) {
      return const ShortcutResult(EditorAction.save);
    }
    if (key == LogicalKeyboardKey.keyG) {
      return const ShortcutResult(EditorAction.toggleGrid);
    }
    return null;
  }
  if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
    return const ShortcutResult(EditorAction.deleteSelected);
  }
  final tool = _toolKeys[key];
  return tool == null ? null : ShortcutResult(EditorAction.tool, tool);
}

final _toolKeys = <LogicalKeyboardKey, EditorTool>{
  LogicalKeyboardKey.keyV: EditorTool.select,
  LogicalKeyboardKey.keyM: EditorTool.move,
  LogicalKeyboardKey.keyB: EditorTool.paintTile,
  LogicalKeyboardKey.keyE: EditorTool.eraseTile,
  LogicalKeyboardKey.keyF: EditorTool.fill,
  LogicalKeyboardKey.keyP: EditorTool.placeEntity,
};
