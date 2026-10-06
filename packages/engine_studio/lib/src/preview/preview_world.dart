import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';

/// A live engine `World` built from an in-memory level, with the platformer
/// systems installed, so the preview runs the same simulation a game would.
///
/// Built from the document as it is right now, edits included, so the preview
/// shows what the designer is looking at without a save or a separate process.
class PreviewWorld {
  final World world;

  /// Entities by the names the level gave them, as [Level.loadInto] returns them.
  final Map<String, EntityId> named;

  /// The player's input, which the keyboard and the on-screen buttons drive. Null
  /// when the level has no player.
  final InputState? input;

  PreviewWorld._(this.world, this.named, this.input);

  /// Loads [document]. Throws [LevelLoadException] when the level is structurally
  /// invalid; component-level problems are the validator's job, and the engine
  /// skips components it cannot read rather than failing the preview.
  factory PreviewWorld.of(
    LevelDocument document, {
    required double width,
    required double height,
  }) {
    final world = World(width: width, height: height);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    registerPlatformerComponents(world);
    final named = Level.loadInto(world, document.toJson());
    final player = named['player'];
    InputState? input;
    if (player != null) {
      input = InputState();
      world.components.storeOf<InputState>().set(player, input);
    }
    installPlatformerSystems(world, player: player, includeAnimation: false);
    return PreviewWorld._(world, named, input);
  }

  /// Advances the simulation by [dt] seconds.
  void step(double dt) => world.step(dt);

  /// Where each entity with a position is now, for drawing.
  Iterable<(EntityId, Position)> get positions sync* {
    final store = world.components.storeOf<Position>();
    for (var i = 0; i < store.length; i++) {
      final id = store.entityAt(i);
      yield (id, store.get(id)!);
    }
  }

  /// Sets which actions the player is holding: `left`, `right`, `jump`, or `dash`.
  /// The platformer input system reads these each step.
  void pressActions(Set<String> actions) {
    final input = this.input;
    if (input == null) return;
    input.pressedActions
      ..clear()
      ..addAll(actions);
  }
}
