import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  World world() {
    final w = World(width: 100, height: 100);
    registerCoreComponents(w);
    registerPlatformerComponents(w);
    return w;
  }

  test('spawnBody gives position, velocity, collider and gravity', () {
    final w = world();
    final id = spawnBody(w, 1, 2, 5);
    expect(w.getComponent<Collider>(id)!.radius, 5);
    expect(w.hasComponent<Gravity>(id), isTrue);
    expect(w.hasComponent<Velocity>(id), isTrue);
  });

  test('gravity: false leaves the body weightless', () {
    final w = world();
    final id = spawnBody(w, 0, 0, 1, gravity: false);
    expect(w.hasComponent<Gravity>(id), isFalse);
  });
}
