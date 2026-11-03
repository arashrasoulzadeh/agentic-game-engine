import '../content/level_document.dart';
import '../content/prefab.dart';
import 'edit_command.dart';

/// Places a [Prefab] in the level at ([x], [y]) as **one** undoable step, however many
/// entities it contains: undo removes the whole group, redo puts back the very same
/// entities.
///
/// The entities are created on the first `apply` (so names are made unique against the
/// level as it is *then*) and reused on redo, so later commands that refer to them by
/// identity (moving one, editing a field) still apply after an undo/redo cycle.
class InstantiatePrefabCommand implements EditCommand {
  final Prefab prefab;
  final double x;
  final double y;

  List<LevelEntity>? _placed;

  InstantiatePrefabCommand(this.prefab, {required this.x, required this.y});

  /// The entities this command placed, or empty before it has been applied.
  List<LevelEntity> get placed => List.unmodifiable(_placed ?? const []);

  @override
  String get label => 'Place ${prefab.name}';

  @override
  void apply(LevelDocument document) {
    _placed ??= prefab.instantiate(
      x,
      y,
      taken: {
        for (final e in document.entities)
          if (e.name != null) e.name!,
      },
    );
    document.entities.addAll(_placed!);
  }

  @override
  void revert(LevelDocument document) {
    for (final e in _placed ?? const <LevelEntity>[]) {
      document.entities.remove(e);
    }
  }
}
