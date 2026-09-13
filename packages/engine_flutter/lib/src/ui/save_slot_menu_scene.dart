import 'package:engine_core/engine_core.dart';

import '../save_game.dart';
import '../scene.dart';
import 'button_menu_scene.dart';

/// One save slot a `SaveSlotMenuScene` shows: which `SaveGame` slot id
/// it reads/writes, and the label to show when it holds a save (an
/// empty slot's label is derived from this — see
/// `SaveSlotMenuScene.slotLabel`).
class SaveSlotSpec {
  final String slot;
  final String label;
  const SaveSlotSpec({required this.slot, required this.label});
}

/// A ready-made save/load slot-picker menu, built on the existing
/// `SaveGame` (`hasSave`) — the "menu" analogue of what
/// `OnScreenControls` already is for touch input: give it a list of
/// slots and what selecting one should do, it handles checking which
/// slots already hold a save and showing that in each button's label.
///
/// Checks `SaveGame.hasSave` for every slot fresh each time this scene
/// is populated (e.g. a return trip to this menu reflects a save made
/// since it was last shown) — one reason this needs its own `populate`
/// override rather than just precomputed `buttons()`, since
/// `SaveGame.hasSave` is async and `ButtonMenuScene.buttons()` isn't.
abstract class SaveSlotMenuScene extends ButtonMenuScene {
  /// The slots this menu shows, top to bottom.
  List<SaveSlotSpec> slots();

  /// Called with the tapped slot's id and whether it currently holds a
  /// save (`SaveGame.hasSave`, checked when this scene was populated —
  /// not re-checked at tap time, so this always matches what the
  /// button's label showed). Typical implementations: load it and
  /// `scenes.loadScene(...)` when `hasSave` is true, or start a fresh
  /// game into that slot (`SaveGame.save`, then switch scenes) when
  /// it's false.
  void onSlotSelected(String slot, bool hasSave, SceneController scenes);

  /// How a slot's button label reflects whether it holds a save.
  /// Override to customize; defaults to appending "(empty)" for a slot
  /// with no save yet.
  String slotLabel(SaveSlotSpec spec, bool hasSave) =>
      hasSave ? spec.label : '${spec.label} (empty)';

  Map<String, bool> _hasSaveBySlot = {};

  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {
    final specs = slots();
    final hasSaveBySlot = <String, bool>{};
    for (final spec in specs) {
      hasSaveBySlot[spec.slot] = await SaveGame.hasSave(slot: spec.slot);
    }
    _hasSaveBySlot = hasSaveBySlot;
    await super.populate(world, scenes, state);
  }

  @override
  List<MenuButtonSpec> buttons() => [
        for (final spec in slots())
          MenuButtonSpec(
            label: slotLabel(spec, _hasSaveBySlot[spec.slot] ?? false),
            actionId: spec.slot,
          ),
      ];

  @override
  void onButtonPressed(String actionId, SceneController scenes) {
    onSlotSelected(actionId, _hasSaveBySlot[actionId] ?? false, scenes);
  }
}
