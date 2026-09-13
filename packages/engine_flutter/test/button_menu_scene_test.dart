import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';

class _RecordingMenu extends ButtonMenuScene {
  final List<String> pressed = [];

  @override
  List<MenuButtonSpec> buttons() => const [
        MenuButtonSpec(label: 'PLAY', actionId: 'play'),
        MenuButtonSpec(label: 'QUIT', actionId: 'quit'),
      ];

  @override
  void onButtonPressed(String actionId, SceneController scenes) {
    pressed.add(actionId);
  }
}

World _buildWorld() {
  final world = World(width: 800, height: 480);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  return world;
}

void main() {
  testWidgets('populate spawns one Button entity per spec, centered on the world',
      (tester) async {
    final menu = _RecordingMenu();
    final world = _buildWorld();
    await menu.populate(world, SceneController(), GameState());

    final buttons = world.storeOf<Button>();
    expect(buttons.length, 2);

    final ids = <String>{};
    for (var i = 0; i < buttons.length; i++) {
      ids.add(buttons.denseAt(i).actionId);
    }
    expect(ids, {'play', 'quit'});

    // Every button is horizontally centered on the world.
    for (var i = 0; i < buttons.length; i++) {
      final entity = buttons.entityAt(i);
      expect(world.storeOf<Position>().get(entity)?.x, world.width / 2);
    }
  });

  testWidgets('loadAssets registers one atlas region per button label', (tester) async {
    final menu = _RecordingMenu();
    final atlasRegistry = await menu.loadAssets();

    expect(atlasRegistry.has(kMenuButtonAtlasId), isTrue);
    final atlas = atlasRegistry.resolve(kMenuButtonAtlasId);
    expect(() => atlas.regionFor('PLAY'), returnsNormally);
    expect(() => atlas.regionFor('QUIT'), returnsNormally);
  });

  testWidgets('handleTap calls onButtonPressed with the tapped button\'s actionId',
      (tester) async {
    final menu = _RecordingMenu();
    final world = _buildWorld();
    final scenes = SceneController();
    await menu.populate(world, scenes, GameState());

    final firstButtonPos = world.storeOf<Position>().get(world.storeOf<Button>().entityAt(0))!;
    menu.handleTap(world, scenes, Offset(firstButtonPos.x, firstButtonPos.y));

    expect(menu.pressed, isNotEmpty);
  });

  testWidgets('handleTap is a no-op when the tap misses every button', (tester) async {
    final menu = _RecordingMenu();
    final world = _buildWorld();
    final scenes = SceneController();
    await menu.populate(world, scenes, GameState());

    menu.handleTap(world, scenes, const Offset(-9999, -9999));

    expect(menu.pressed, isEmpty);
  });

  test('ambientBrightness overrides to 1.0 so a menu never darkens with gameplay lighting', () {
    expect(_RecordingMenu().ambientBrightness, 1.0);
  });
}
