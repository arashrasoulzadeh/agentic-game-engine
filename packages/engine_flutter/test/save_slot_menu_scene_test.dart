import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingSaveSlotMenu extends SaveSlotMenuScene {
  final List<(String, bool)> selections = [];

  @override
  List<SaveSlotSpec> slots() => const [
        SaveSlotSpec(slot: 'a', label: 'Slot A'),
        SaveSlotSpec(slot: 'b', label: 'Slot B'),
      ];

  @override
  void onSlotSelected(String slot, bool hasSave, SceneController scenes) {
    selections.add((slot, hasSave));
  }
}

World _buildWorld() {
  final world = World(width: 800, height: 480);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  return world;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('populate labels each slot as empty when no save exists', (tester) async {
    final menu = _RecordingSaveSlotMenu();
    final world = _buildWorld();
    await menu.populate(world, SceneController(), GameState());

    // One Button entity per slot was actually spawned (ButtonMenuScene's
    // job); the labels themselves are read back via buttons() below,
    // same as loadAssets does to build the menu's atlas.
    expect(world.storeOf<Button>().length, 2);
    expect(menu.buttons().map((b) => b.label), ['Slot A (empty)', 'Slot B (empty)']);
  });

  testWidgets('populate labels a slot that holds a save without "(empty)"', (tester) async {
    final saved = _buildWorld()..spawn();
    await SaveGame.save(saved, slot: 'a');

    final menu = _RecordingSaveSlotMenu();
    final world = _buildWorld();
    await menu.populate(world, SceneController(), GameState());

    expect(menu.buttons().map((b) => b.label), ['Slot A', 'Slot B (empty)']);
  });

  testWidgets('onButtonPressed reports the tapped slot id and its hasSave state',
      (tester) async {
    final saved = _buildWorld()..spawn();
    await SaveGame.save(saved, slot: 'a');

    final menu = _RecordingSaveSlotMenu();
    final world = _buildWorld();
    final scenes = SceneController();
    await menu.populate(world, scenes, GameState());

    final slotAPos = world.storeOf<Position>().get(
          world.storeOf<Button>().entityAt(0),
        )!;
    menu.handleTap(world, scenes, Offset(slotAPos.x, slotAPos.y));

    expect(menu.selections, [('a', true)]);
  });

  testWidgets('a return trip reflects a save made since the last populate', (tester) async {
    final menu1 = _RecordingSaveSlotMenu();
    await menu1.populate(_buildWorld(), SceneController(), GameState());
    expect(menu1.buttons().map((b) => b.label), ['Slot A (empty)', 'Slot B (empty)']);

    final saved = _buildWorld()..spawn();
    await SaveGame.save(saved, slot: 'b');

    final menu2 = _RecordingSaveSlotMenu();
    await menu2.populate(_buildWorld(), SceneController(), GameState());
    expect(menu2.buttons().map((b) => b.label), ['Slot A (empty)', 'Slot B']);
  });
}
