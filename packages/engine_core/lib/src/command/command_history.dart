import '../content/level_document.dart';
import 'edit_command.dart';

/// Undo and redo stacks for a [LevelDocument]. Every edit goes through
/// [execute]; a new edit after an undo discards the redo stack, the usual
/// editor behavior.
class CommandHistory {
  final LevelDocument document;
  final List<EditCommand> _undo = [];
  final List<EditCommand> _redo = [];

  CommandHistory(this.document);

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Label of the command the next [undo] reverts, or null.
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;

  /// Label of the command the next [redo] re-applies, or null.
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;

  void execute(EditCommand command) {
    command.apply(document);
    _undo.add(command);
    _redo.clear();
  }

  /// Reverts the most recent command. Does nothing when there is none.
  void undo() {
    if (_undo.isEmpty) return;
    final command = _undo.removeLast();
    command.revert(document);
    _redo.add(command);
  }

  /// Re-applies the most recently undone command. Does nothing when there is none.
  void redo() {
    if (_redo.isEmpty) return;
    final command = _redo.removeLast();
    command.apply(document);
    _undo.add(command);
  }
}
