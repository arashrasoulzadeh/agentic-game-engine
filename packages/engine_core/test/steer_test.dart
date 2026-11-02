import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

SteerContext _ctx({Position? target, double selfX = 0}) => SteerContext(
  self: Position(selfX, 0),
  current: Velocity(1, 0),
  rng: DeterministicRandom(1),
  target: target,
);

void main() {
  test('seek and flee are opposites', () {
    final c = _ctx(target: Position(10, 0));
    expect(Steer.seek(5)(c).x, closeTo(5, 1e-9));
    expect(Steer.flee(5)(c).x, closeTo(-5, 1e-9));
  });

  test('rules that need a target stand still without one', () {
    final c = _ctx();
    for (final rule in [
      Steer.seek(5),
      Steer.flee(5),
      Steer.arrive(5, slowRadius: 3),
    ]) {
      final v = rule(c);
      expect([v.x, v.y], [0, 0]);
    }
  });

  test('arrive slows inside the radius', () {
    final rule = Steer.arrive(10, slowRadius: 10);
    expect(rule(_ctx(target: Position(5, 0))).x, closeTo(5, 1e-9));
    expect(rule(_ctx(target: Position(50, 0))).x, closeTo(10, 1e-9));
  });

  test('blend adds weighted rules and never exceeds maxSpeed', () {
    final c = _ctx(target: Position(10, 0));
    final half = Steer.blend([(Steer.seek(10), 0.5)], maxSpeed: 100)(c);
    expect(half.x, closeTo(5, 1e-9));
    final capped = Steer.blend([
      (Steer.seek(10), 1),
      (Steer.seek(10), 1),
    ], maxSpeed: 12)(c);
    expect(capped.x, closeTo(12, 1e-9));
  });

  test('firstMoving falls through zero-velocity rules', () {
    final c = _ctx(target: Position(10, 0));
    final rule = Steer.firstMoving([
      Steer.onlyWhen(Steer.within(2), Steer.flee(5)),
      Steer.seek(3),
    ]);
    expect(rule(c).x, closeTo(3, 1e-9), reason: 'too far to flee');
    expect(rule(_ctx(target: Position(1, 0))).x, closeTo(-5, 1e-9));
  });

  test('wander is reproducible for the same seed', () {
    Velocity run() => Steer.wander(0.5, 10)(_ctx());
    expect(run().x, run().x);
    expect(run().y, run().y);
  });
}
