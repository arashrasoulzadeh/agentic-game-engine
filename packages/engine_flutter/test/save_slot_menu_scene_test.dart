import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tiny real PNG, rasterized rather than hand-built -- `loadAssets`
/// decodes a saved thumbnail with `ui.instantiateImageCodec`, which
/// needs real, valid image bytes, not just any `Uint8List`.
Future<Uint8List> _tinyPng({int width = 8, int height = 4}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

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

  // Plain test(), not testWidgets(): loadAssets decodes the thumbnail
  // via ui.instantiateImageCodec, which (per sprite_atlas_test.dart's
  // own tests, all plain test() too) resolves fine outside a
  // testWidgets fake-async zone -- it's specifically that zone
  // combined with GameRunner's continuously-rescheduling Ticker that
  // deadlocks real codec work (see packed_atlas_test.dart's doc
  // comment), and nothing here ever mounts a GameRunner/Ticker.
  test('loadAssets registers a thumbnail atlas for a slot with a saved screenshot, '
      'and onButtonSpawned positions it to the left of that slot\'s button', () async {
    final thumbnail = await _tinyPng(width: 80, height: 40);
    final saved = _buildWorld()..spawn();
    await SaveGame.save(saved, slot: 'a', thumbnail: thumbnail);

    final menu = _RecordingSaveSlotMenu();
    final world = _buildWorld();
    await menu.populate(world, SceneController(), GameState());
    final registry = await menu.loadAssets();

    expect(registry.has('save_slot_thumbnail_a'), isTrue);
    expect(registry.has('save_slot_thumbnail_b'), isFalse);

    final buttonEntity = world.storeOf<Button>().entityAt(0);
    final buttonPos = world.storeOf<Position>().get(buttonEntity)!;

    // onButtonSpawned already ran during populate (ButtonMenuScene
    // spawns buttons before loadAssets is ever called). Both slots'
    // generated-rect buttons each carry their own Sprite too (the
    // engine's own runtime-built button art), so the thumbnail is
    // found by its distinct atlas id, not by entity count alone.
    final sprites = world.storeOf<Sprite>();
    expect(sprites.length, 3); // 2 buttons + 1 thumbnail
    final thumbEntity = [
      for (var i = 0; i < sprites.length; i++) sprites.entityAt(i),
    ].firstWhere((e) => sprites.get(e)!.atlasId == 'save_slot_thumbnail_a');

    final thumbPos = world.storeOf<Position>().get(thumbEntity)!;
    expect(thumbPos.x, lessThan(buttonPos.x));
    expect(thumbPos.y, buttonPos.y);
  });

  test('a slot with no saved thumbnail spawns no extra Sprite entity for it', () async {
    final menu = _RecordingSaveSlotMenu();
    final world = _buildWorld();
    await menu.populate(world, SceneController(), GameState());
    await menu.loadAssets();

    // Just the 2 generated-rect buttons' own Sprites, no thumbnails.
    expect(world.storeOf<Sprite>().length, 2);
  });
}
