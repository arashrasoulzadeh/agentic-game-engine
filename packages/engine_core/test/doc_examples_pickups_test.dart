// Mirrors docs/examples/pickups-doors-waves.md; keep the two in sync.
import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _KeyPicked {}

void main() {
  World newWorld() {
    final world = World(width: 200, height: 100);
    registerCoreComponents(world);
    return world;
  }

  test('pickup: touching a tagged coin removes it and counts it', () {
    final world = newWorld();
    final player = world.spawnAt(0, 0);
    world.spawnWith([
      Position(3, 0),
      EntityTags(['coin']),
    ]);
    world.spawnWith([
      Position(90, 0),
      EntityTags(['coin']),
    ]);
    var coins = 0;
    world.addSystemFn('pickup', (world, dt) {
      final p = world.getComponent<Position>(player)!;
      for (final id in world.findNear(p.x, p.y, 8, exclude: player)) {
        if (world.hasTag(id, 'coin')) {
          world.commands.destroy(id);
          coins++;
        }
      }
    });
    world.step(1 / 60);
    expect(coins, 1);
    expect(world.withTag('coin').length, 1);
  });

  test('door and key: picking the key opens the door via an event', () {
    final world = newWorld();
    final door = world.spawnWith([
      Position(50, 0),
      EntityTags(['door']),
    ]);
    world.on<_KeyPicked>((_) {
      for (final id in world.withTag('door').toList()) {
        world.commands.destroy(id);
      }
    });
    world.events.emit(_KeyPicked());
    world.step(1 / 60);
    expect(world.entities.isAlive(door), isFalse);
  });

  test('patrol: a system turns the enemy around at its bounds', () {
    final world = newWorld();
    final enemy = world.spawnWith([Position(0, 0), Velocity(60, 0)]);
    world.addSystemFn('patrol', (world, dt) {
      for (final (_, pos, vel) in world.query2<Position, Velocity>()) {
        if (pos.x > 20 && vel.x > 0 || pos.x < 0 && vel.x < 0) vel.x = -vel.x;
      }
    }, phase: SystemPhase.prePhysics);
    SystemPresets.core(world);
    for (var i = 0; i < 120; i++) {
      world.step(1 / 60);
    }
    final x = world.getComponent<Position>(enemy)!.x;
    expect(x, inInclusiveRange(-2, 22));
  });

  test('wave: a sequence spawns enemies on a schedule', () {
    final world = newWorld();
    world.sequence([
      SeqStep.run(() => world.spawnAt(0, 0)),
      const SeqStep.wait(2),
      SeqStep.run(() => world.spawnAt(10, 0)),
    ]);
    world.step(0.5);
    expect(world.componentsOf<Position>().length, 1);
    world.step(1.5);
    expect(world.componentsOf<Position>().length, 2);
  });
}
