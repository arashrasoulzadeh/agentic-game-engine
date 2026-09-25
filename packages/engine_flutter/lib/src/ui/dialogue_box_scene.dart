import 'package:engine_core/engine_core.dart';

import '../logic/scene.dart' show SceneController;
import '../rendering/sprite.dart';
import '../rendering/text.dart' show Text, TextAlignment;
import 'button_menu_scene.dart';

/// A ready-made dialogue box scene that renders a [DialogueRunner]'s
/// current node text and choices as vertically-stacked buttons.
/// Subclass to provide the runner and handle choice events.
abstract class DialogueBoxScene extends ButtonMenuScene {
  /// The [DialogueRunner] driving this dialogue. Must be set before
  /// `populate` is called (typically in the subclass's constructor or
  /// via `GameState`).
  late final DialogueRunner runner;

  /// The [StringTable] used to resolve text keys. Must be set before
  /// `populate` is called.
  late final StringTable stringTable;

  /// Override to return a custom atlas/region for dialogue box background.
  /// Defaults to the engine's generated rounded-rect atlas.
  String? get dialogueBoxAtlasId => null;

  /// Override to return a custom atlas/region for dialogue box background.
  /// Defaults to the engine's generated rounded-rect atlas.
  String? get dialogueBoxRegion => null;

  // Internal reference to the world, set during populate
  World? _world;

  /// Called when the player selects a choice.
  /// By default, calls [runner.advance] and emits the choice's event.
  /// Override to add custom logic (e.g. playing a sound, updating quest state).
  void onChoiceSelected(
      DialogueChoice choice, World world, SceneController scenes) {
    runner.advance(world, _choiceIndex(choice));
    // If dialogue ended, typically pop this overlay or load next scene
    if (runner.currentNode == null) {
      scenes.popOverlay();
    }
  }

  /// Finds the index of [choice] in the current node's choices list.
  /// Returns -1 if not found (shouldn't happen for a valid choice).
  int _choiceIndex(DialogueChoice choice) {
    final node = runner.currentNode;
    if (node == null) return -1;
    return node.choices.indexOf(choice);
  }

  @override
  List<MenuButtonSpec> buttons() {
    final world = _world;
    if (world == null) return [];
    final choices = runner.availableChoices(WorldView(world));
    return choices.map((choice) {
      return MenuButtonSpec(
        label: stringTable.resolve(choice.textKey),
        actionId: choice.textKey, // use textKey as actionId; choice object matched in onButtonPressed
        labelFontSize: 18,
      );
    }).toList();
  }

  @override
  void onButtonPressed(String actionId, SceneController scenes) {
    final world = _world;
    if (world == null) return;
    final choices = runner.availableChoices(WorldView(world));
    DialogueChoice? choice;
    for (final c in choices) {
      if (c.textKey == actionId) {
        choice = c;
        break;
      }
    }
    if (choice != null) {
      onChoiceSelected(choice, world, scenes);
    }
  }

  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {
    _world = world;

    // Add dialogue box background if specified
    if (dialogueBoxAtlasId != null && dialogueBoxRegion != null) {
      final bg = world.spawn();
      world.storeOf<Position>().set(bg, Position(0, 0));
      world.storeOf<Sprite>().set(bg, Sprite(
        dialogueBoxAtlasId!,
        dialogueBoxRegion!,
        zIndex: -5,
        scaleX: 800 / 200, // scale to cover viewport width
        scaleY: 600 / 150, // scale to cover viewport height
      ));
    }

    // Add dialogue text as a Text entity
    final textEntity = world.spawn();
    world.storeOf<Position>().set(textEntity, Position(400, 100));
    world.storeOf<Text>().set(textEntity, Text(
      runner.visibleText(WorldView(world)) ?? '',
      colorArgb: 0xFFFFFFFF,
      fontSize: 24,
      align: TextAlignment.center,
    ));

    await super.populate(world, scenes, state);
  }
}