import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('Position and Velocity default to zero and keep positional use', () {
    expect([Position().x, Position().y], [0, 0]);
    expect([Velocity().x, Velocity().y], [0, 0]);
    final p = Position(3, 4);
    expect([p.x, p.y], [3, 4]);
    expect(Position(5).y, 0, reason: 'x alone is allowed');
    expect(Velocity(1, 2).y, 2);
  });

  test('defaults flow through spawnWith and JSON unchanged', () {
    final w = World(width: 10, height: 10);
    registerCoreComponents(w);
    final id = w.spawnWith([Position(), Velocity()]);
    expect(w.components.serializeEntity(id)['position'], {'x': 0.0, 'y': 0.0});
    expect(
      () => Position.fromJson({'x': 1}),
      throwsA(anything),
      reason: 'JSON still requires both fields',
    );
  });
}
