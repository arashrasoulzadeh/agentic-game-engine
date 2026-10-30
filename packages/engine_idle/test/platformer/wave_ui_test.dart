import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' as eng;
import 'package:engine_idle/engine_idle.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World buildWorld() {
  final world = World(width: 180, height: 320);
  registerCoreComponents(world);
  eng.registerFlutterComponents(world);
  registerPlatformerComponents(world);
  return world;
}

void main() {
  test('SpriteHealthBar shrinks its fill from the left edge with Health', () {
    final world = buildWorld();
    final owner = world.spawn();
    world.storeOf<Health>().set(owner, Health(current: 100, max: 100));
    final bar = SpriteHealthBar.spawn(
      world,
      atlasId: 'ui_bars',
      source: owner,
      left: 10,
      top: 4,
      width: 107, // scale 1 against the 107px frame
    );
    final sprites = world.storeOf<eng.Sprite>();
    final pos = world.storeOf<Position>();
    // entity 1 = frame, 2 = fill
    final fillId = world.storeOf<eng.Sprite>().entityAt(1);
    double fillW() => sprites.get(fillId)!.scaleX * BarsArt.fillSize.w;

    expect(fillW(), closeTo(BarsArt.innerWidth, 1e-6));
    final leftEdgeFull = pos.get(fillId)!.x - fillW() / 2;

    world.storeOf<Health>().get(owner)!.current = 25;
    bar.sync();
    expect(fillW(), closeTo(BarsArt.innerWidth * 0.25, 1e-6));
    // the left edge stays put while the right edge retreats
    expect(pos.get(fillId)!.x - fillW() / 2, closeTo(leftEdgeFull, 1e-6));

    world.storeOf<Health>().get(owner)!.current = 0;
    bar.sync();
    expect(fillW(), 0);

    bar.setFill('boss');
    expect(sprites.get(fillId)!.region, 'fill_boss');
    bar.destroy();
    expect(sprites.length, 0);
  });

  test('WavePath marks cleared, current, locked and the boss node', () {
    final world = buildWorld();
    final path = WavePath.spawn(
      world,
      nodesAtlasId: 'nodes',
      lineAtlasId: 'line',
      count: 5,
      y: 38,
      left: 10,
      right: 170,
      nodeSize: 8,
    );
    List<String> regions() {
      final s = world.storeOf<eng.Sprite>();
      return [
        for (var i = 0; i < s.length; i++)
          if (s.denseAt(i).atlasId == 'nodes') s.denseAt(i).region,
      ];
    }

    expect(regions(), ['1', '0', '0', '0', '3']);
    path.update(2, 8);
    expect(regions(), ['2', '2', '1', '0', '3']);
    path.update(4, 8); // the boss encounter
    expect(regions(), ['2', '2', '2', '2', '3']);

    // nodes span the given width, evenly
    final xs = [
      for (var i = 0; i < world.storeOf<eng.Sprite>().length; i++)
        if (world.storeOf<eng.Sprite>().denseAt(i).atlasId == 'nodes')
          world
              .storeOf<Position>()
              .get(world.storeOf<eng.Sprite>().entityAt(i))!
              .x,
    ];
    expect(xs.first, 10);
    expect(xs.last, 170);
    expect(xs[1] - xs[0], closeTo(40, 1e-9));
  });

  test('the caption backdrop opens with the text and closes after it', () {
    final world = buildWorld();
    final caption = DialogueCaption.spawn(
      world,
      style: const HudTextStyle(x: 90, y: 160),
      backdropAtlasId: 'scroll',
      backdropWidth: 128,
      backdropHeight: 78,
    );
    double scale() => world.storeOf<eng.Sprite>().denseAt(0).scaleX;

    expect(scale(), 0);
    caption.show(world, 'hello world');
    for (var i = 0; i < 10; i++) {
      caption.update(world, 0.05);
    }
    expect(scale(), closeTo(1, 1e-9));

    caption.hide();
    for (var i = 0; i < 40; i++) {
      caption.update(world, 0.05);
    }
    expect(caption.visible, isFalse);
    expect(scale(), 0);
  });
}
