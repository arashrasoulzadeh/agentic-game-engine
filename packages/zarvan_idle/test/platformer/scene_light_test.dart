import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;
import 'package:zarvan_idle/zarvan_idle.dart';
import 'package:flutter_test/flutter_test.dart';

World _world() {
  final world = World(width: 180, height: 320);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  return world;
}

EntityId _light(World world) {
  final id = world.spawn();
  world.componentsOf<Position>().set(id, Position(0, 0));
  world.componentsOf<Light2D>().set(id, Light2D(radius: 50));
  return id;
}

EntityId _unit(World world, double x, double y) {
  final id = world.spawn();
  world.componentsOf<Position>().set(id, Position(x, y));
  return id;
}

void main() {
  test('lights follow their anchors with the configured offset', () {
    final world = _world();
    final hero = _unit(world, 40, 200);
    final enemy = _unit(world, 140, 210);
    final specs = [
      const SceneLight(anchor: LightAnchor.hero, x: 5, y: -30, radius: 50),
      const SceneLight(anchor: LightAnchor.enemy, radius: 40),
      const SceneLight(x: 20, y: 235, radius: 30),
    ];
    final ids = [for (final _ in specs) _light(world)];
    final system = SceneLightSystem(specs, ids, () => hero, () => enemy)
      ..update(world, 0.016);

    final pos = world.componentsOf<Position>();
    expect((pos.get(ids[0])!.x, pos.get(ids[0])!.y), (45, 170));
    expect((pos.get(ids[1])!.x, pos.get(ids[1])!.y), (140, 210));
    expect((pos.get(ids[2])!.x, pos.get(ids[2])!.y), (20, 235));
    expect(world.componentsOf<Light2D>().get(ids[2])!.radius, 30);
    expect(system.name, 'SceneLightSystem');
  });

  test('an anchored light with no target is switched off', () {
    final world = _world();
    final id = _light(world);
    SceneLightSystem(
      const [SceneLight(anchor: LightAnchor.enemy, radius: 40)],
      [id],
      () => null,
      () => null,
    ).update(world, 0.016);
    expect(world.componentsOf<Light2D>().get(id)!.radius, 0);

    final dead = _unit(world, 1, 1);
    world.destroy(dead);
    SceneLightSystem(
      const [SceneLight(anchor: LightAnchor.enemy, radius: 40)],
      [id],
      () => null,
      () => dead,
    ).update(world, 0.016);
    expect(world.componentsOf<Light2D>().get(id)!.radius, 0);
  });

  test('flicker wobbles the radius within +-flicker and 0 keeps it steady', () {
    final world = _world();
    final id = _light(world);
    final system = SceneLightSystem(
      const [SceneLight(radius: 100, flicker: 0.1)],
      [id],
      () => null,
      () => null,
    );
    final seen = <double>{};
    for (var i = 0; i < 60; i++) {
      system.update(world, 0.016);
      seen.add(world.componentsOf<Light2D>().get(id)!.radius);
    }
    expect(seen.length, greaterThan(10));
    expect(seen.every((r) => r >= 90 && r <= 110), isTrue);
  });

  test('WaveCombatConfig carries a list of lights, empty by default', () {
    const plain = WaveCombatConfig(
      heroStem: 'h',
      enemyRoot: 'e',
      backgroundDir: 'b',
      backgroundPrefix: 'bg',
    );
    expect(plain.lights, isEmpty);
  });
}
