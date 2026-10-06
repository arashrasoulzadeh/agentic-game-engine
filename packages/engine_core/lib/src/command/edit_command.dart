import '../content/level_document.dart';

/// One undoable change to a [LevelDocument]. The studio performs every edit as
/// a command, so an edit can be undone exactly and an agent can apply the same
/// edits headlessly.
///
/// Contract: [revert] called right after [apply] restores the document exactly
/// as it was, including key order. The command records what it needs at apply
/// time, since its inputs can be gone by the time it is reverted.
abstract class EditCommand {
  /// Short human-readable name for the undo menu, e.g. "Move player".
  String get label;

  void apply(LevelDocument document);

  void revert(LevelDocument document);
}
