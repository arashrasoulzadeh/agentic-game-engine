import '../content/level_document.dart';
import 'edit_command.dart';

/// Several commands recorded as one undo step, such as a whole paint stroke or a
/// multi-entity move. Apply runs the parts in order; revert runs them in reverse,
/// so each part sees exactly the document state it left behind.
class CompositeCommand implements EditCommand {
  @override
  final String label;

  final List<EditCommand> commands;

  CompositeCommand(this.label, this.commands);

  @override
  void apply(LevelDocument document) {
    for (final command in commands) {
      command.apply(document);
    }
  }

  @override
  void revert(LevelDocument document) {
    for (final command in commands.reversed) {
      command.revert(document);
    }
  }
}
