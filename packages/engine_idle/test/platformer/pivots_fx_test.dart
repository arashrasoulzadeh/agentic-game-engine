import 'dart:typed_data';

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_idle/engine_idle.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

/// RGBA strip of [frames] cells where each frame is one opaque column block.
Uint8List strip(int cell, int gap, List<({int x, int y0, int y1, int w})> f) {
  final w = gap + f.length * (cell + gap);
  final out = Uint8List(w * cell * 4);
  for (var i = 0; i < f.length; i++) {
    final b = f[i];
    for (var y = b.y0; y < b.y1; y++) {
      for (var x = b.x; x < b.x + b.w; x++) {
        out[(y * w + gap + i * (cell + gap) + x) * 4 + 3] = 255;
      }
    }
  }
  return out;
}

void main() {
  test('sheetPivots finds the feet, not the weapon-skewed bbox centre', () {
    const cell = 32, gap = 4;
    final data = strip(cell, gap, [
      (x: 10, y0: 4, y1: 30, w: 4), // plain standing frame
      (x: 10, y0: 10, y1: 26, w: 4), // shorter pose, feet higher
    ]);
    // widen frame 1 with a "spear" high up, away from the feet
    final w = gap + 2 * (cell + gap);
    for (var y = 12; y < 14; y++) {
      for (var x = 20; x < 30; x++) {
        data[(y * w + gap + (cell + gap) + x) * 4 + 3] = 255;
      }
    }
    final p = sheetPivots(data, w, cell, cell: cell, gap: gap, frames: 2);
    expect(p[0].x, 12);
    expect(p[0].y, 30);
    expect(p[1].x, 12);
    expect(p[1].y, 26);
  });

  test('PivotTable offsets keep feet where the idle reference stands', () {
    final t = PivotTable()
      ..register('idle', [const Pivot(10, 30)])
      ..register('atk', [const Pivot(14, 26)]);
    final o = t.offsetFor('atk', '0', 'idle')!;
    expect((o.x, o.y), (-4, 4));
    expect(t.offsetFor('atk', '3', 'idle'), isNull);
  });

  test('FighterPivotSystem writes the offset onto the sprite', () {
    final world = World(width: 180, height: 320);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    registerPlatformerComponents(world);
    registerCombatComponents(world);
    final table = PivotTable()
      ..register('a_idle', [const Pivot(10, 30)])
      ..register('a_attack', [const Pivot(16, 28), const Pivot(12, 30)]);
    world.addSystem(FighterPivotSystem(table));
    final e = spawnFighter(
      world,
      side: 'hero',
      x: 0,
      y: 0,
      hp: 1,
      attack: 1,
      attackSpeed: 1,
      armor: 0,
      atlasId: 'a_idle',
      frameCount: 1,
    );
    final s = world.storeOf<Sprite>().get(e)!
      ..atlasId = 'a_attack'
      ..region = '0';
    world.step(0.016);
    expect((s.offsetX, s.offsetY), (-6, 2));
  });

  test('a hit spawns spark fx; a fatal hit adds smoke; fx expire', () {
    final world = World(width: 180, height: 320);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    registerPlatformerComponents(world);
    registerCombatComponents(world);
    world
      ..addSystem(AutoCombatSystem())
      ..addSystem(AnimationSystem())
      ..addSystem(FxSystem());
    installCombatFx(
      world,
      const CombatFx(hit: FxClip('spark', 2), death: FxClip('smoke', 2)),
    );
    for (final side in ['hero', 'enemy']) {
      spawnFighter(
        world,
        side: side,
        x: 10,
        y: 10,
        hp: side == 'hero' ? 100 : 5,
        attack: 50,
        attackSpeed: 1,
        armor: 0,
        atlasId: '${side}_idle',
        frameCount: 1,
      );
    }
    world.step(0.01);
    final fx = world.storeOf<FxLife>();
    expect(fx.length, 3); // two sparks (both fighters hit) + one fatal smoke
    for (var i = 0; i < 10; i++) {
      world.step(0.1);
    }
    expect(fx.length, 0);
  });
}
