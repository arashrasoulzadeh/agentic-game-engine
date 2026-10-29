import 'dart:typed_data';

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// RGBA strip with one opaque block per frame.
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
      (x: 10, y0: 4, y1: 30, w: 4),
      (x: 10, y0: 10, y1: 26, w: 4),
    ]);
    final w = gap + 2 * (cell + gap);
    for (var y = 12; y < 14; y++) {
      for (var x = 20; x < 30; x++) {
        data[(y * w + gap + (cell + gap) + x) * 4 + 3] = 255; // a "spear"
      }
    }
    final p = sheetPivots(data, w, cell, cell: cell, gap: gap, frames: 2);
    expect((p[0].x, p[0].y, p[0].top), (12, 30, 4));
    expect((p[1].x, p[1].y), (12, 26));
  });

  test('PivotTable offsets keep feet where the reference frame stands', () {
    final t = PivotTable()
      ..register('idle', [const Pivot(10, 30, 4)])
      ..register('atk', [const Pivot(14, 26)]);
    final o = t.offsetFor('atk', '0', 'idle')!;
    expect((o.x, o.y), (-4, 4));
    expect(t.offsetFor('atk', '3', 'idle'), isNull);
    final b = t.bodyOf('idle')!;
    expect((b.bottom, b.top, b.cell), (30, 4, 64));
  });

  test('SpritePivotSystem writes the offset onto the sprite', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    final table = PivotTable()
      ..register('a_idle', [const Pivot(10, 30)])
      ..register('a_attack', [const Pivot(16, 28), const Pivot(12, 30)]);
    world.addSystem(SpritePivotSystem(table));
    final e = world.spawn();
    final sprite = Sprite('a_attack', '0');
    world.storeOf<Sprite>().set(e, sprite);
    world.storeOf<SpriteStates>().set(
      e,
      SpriteStates({
        'idle': const SpriteClip(atlasId: 'a_idle', frames: 1, loop: true),
      }),
    );
    world.step(0.016);
    expect((sprite.offsetX, sprite.offsetY), (-6, 2));
  });
}
