import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_idle/engine_idle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late World world;
  late EntityId hero;
  late EntityId enemy;
  late EntityId corpse;
  late WalkPhase walk;

  EntityId at(double x, double y) {
    final e = world.spawn();
    world.storeOf<Position>().set(e, Position(x, y));
    return e;
  }

  setUp(() {
    world = World(width: 180, height: 320);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    world.addSystem(TweenSystem());
    final scroller = ParallaxScroller.spawn(world, 'bg', const [
      ParallaxSpec('near', 1),
    ]);
    walk = WalkPhase(scroller: scroller, speed: 100, distance: 200);
    hero = at(40, 200);
    corpse = at(100, 200);
    enemy = at(100 + 200, 200); // starts `distance` right of its anchor
  });

  test(
    'the enemy arrives at its anchor, the corpse leaves and the walk ends',
    () {
      walk.start(world, hero: hero, enemy: enemy, corpse: corpse);
      expect(walk.active, isTrue);

      var finished = false;
      for (var i = 0; i < 400 && !finished; i++) {
        world.step(0.016);
        finished = walk.update(world);
      }

      expect(finished, isTrue);
      expect(walk.active, isFalse);
      expect(world.storeOf<Position>().get(enemy)!.x, closeTo(100, 1e-6));
      expect(world.storeOf<Position>().get(hero)!.y, 200);
      expect(world.storeOf<Position>().has(corpse), isFalse);
    },
  );

  test('scenery and the corpse move by the distance walked', () {
    walk.start(world, hero: hero, enemy: enemy, corpse: corpse);
    for (var i = 0; i < 400; i++) {
      world.step(0.016);
      if (walk.update(world)) break;
    }
    final layers = world.storeOf<ParallaxLayer>();
    final x = world.storeOf<Position>().get(layers.entityAt(0))!.x;
    expect(x, closeTo(-200, 1e-6)); // speed 1 x distance 200, to the left
  });

  test('the hero lifts while walking and the walk takes distance / speed', () {
    walk.start(world, hero: hero, enemy: enemy);
    var seenLift = false;
    var elapsed = 0.0;
    while (elapsed < 10) {
      world.step(0.016);
      elapsed += 0.016;
      final done = walk.update(world);
      if (world.storeOf<Position>().get(hero)!.y < 200) seenLift = true;
      if (done) break;
    }
    expect(seenLift, isTrue);
    expect(elapsed, closeTo(2.0, 0.05)); // 200 units at 100/s
  });
}
