import '../content/level_document.dart';
import 'composite_command.dart';
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

  /// Applies [commands] as one undo step labelled [label], such as a paint
  /// stroke made of many tile edits. Nothing is recorded when [commands] is empty.
  void executeGroup(String label, List<EditCommand> commands) {
    if (commands.isEmpty) return;
    execute(CompositeCommand(label, commands));
  }

  /// Records [command] as the latest undo step without applying it, for edits
  /// that were already applied step by step. A paint stroke is the case: each
  /// cell must be applied as it is painted, so the next cell sees the last one.
  void recordApplied(EditCommand command) {
    _undo.add(command);
    _redo.clear();
  }

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
