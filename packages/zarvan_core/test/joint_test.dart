import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:zarvan_core/zarvan_core.dart';

World _world() {
  final world = World(width: 1000, height: 1000);
  registerCoreComponents(world);
  world.addSystem(JointSystem());
  world.addSystem(MovementSystem());
  return world;
}

EntityId _body(
  World world,
  double x,
  double y, {
  double vx = 0,
  double vy = 0,
}) {
  final id = world.spawn();
  world.componentsOf<Position>().set(id, Position(x, y));
  world.componentsOf<Velocity>().set(id, Velocity(vx, vy));
  return id;
}

double _dist(World world, EntityId a, EntityId b) {
  final p = world.componentsOf<Position>();
  final dx = p.get(a)!.x - p.get(b)!.x, dy = p.get(a)!.y - p.get(b)!.y;
  return math.sqrt(dx * dx + dy * dy);
}

void main() {
  test('a damped spring settles at its rest length', () {
    final world = _world();
    final a = _body(world, 0, 0);
    final b = _body(world, 120, 0); // stretched: rest is 50
    world.componentsOf<Joint>().set(
      a,
      Joint(other: b, length: 50, stiffness: 60, damping: 6),
    );
    for (var i = 0; i < 600; i++) {
      world.step(0.016);
    }
    expect(_dist(world, a, b), closeTo(50, 0.5));
  });

  test('an undamped spring keeps oscillating around the rest length', () {
    final world = _world();
    final a = _body(world, 0, 0);
    final b = _body(world, 100, 0);
    world.componentsOf<Joint>().set(
      a,
      Joint(other: b, length: 50, stiffness: 50, damping: 0),
    );
    var min = 1e9, max = 0.0;
    for (var i = 0; i < 400; i++) {
      world.step(0.005);
      final d = _dist(world, a, b);
      min = math.min(min, d);
      max = math.max(max, d);
    }
    expect(min, lessThan(50));
    expect(max, greaterThan(50));
  });

  test('a rope is slack inside its length and pulls when taut', () {
    final world = _world();
    final a = _body(world, 0, 0);
    final b = _body(world, 30, 0, vx: 5); // slack: 30 < 50
    world.componentsOf<Joint>().set(
      a,
      Joint(kind: JointKind.rope, other: b, length: 50, stiffness: 200),
    );
    world.step(0.016);
    expect(world.componentsOf<Velocity>().get(b)!.x, 5); // untouched
    world.componentsOf<Position>().get(b)!.x = 90; // now taut
    world.componentsOf<Velocity>().get(b)!.x = 0;
    world.step(0.016);
    expect(
      world.componentsOf<Velocity>().get(b)!.x,
      lessThan(0),
    ); // pulled back
    expect(world.componentsOf<Velocity>().get(a)!.x, greaterThan(0));
  });

  test('a rod to a fixed point makes a pendulum that keeps its length', () {
    final world = _world();
    final bob = _body(
      world,
      300,
      100,
      vx: 80,
    ); // pivot at (200,100), length 100
    world.componentsOf<Joint>().set(
      bob,
      Joint(kind: JointKind.rod, anchorX: 200, anchorY: 100, length: 100),
    );
    var worst = 0.0;
    for (var i = 0; i < 300; i++) {
      world.componentsOf<Velocity>().get(bob)!.y += 400 * 0.016; // gravity
      world.step(0.016);
      final p = world.componentsOf<Position>().get(bob)!;
      final d = math.sqrt(
        (p.x - 200) * (p.x - 200) + (p.y - 100) * (p.y - 100),
      );
      worst = math.max(worst, (d - 100).abs());
    }
    expect(worst, lessThan(3));
    // it swung: it is no longer at the start position
    expect(world.componentsOf<Position>().get(bob)!.y, isNot(100));
  });

  test('a rod between two entities shares the correction equally', () {
    final world = _world();
    final a = _body(world, 0, 0);
    final b = _body(world, 100, 0);
    world.componentsOf<Joint>().set(
      a,
      Joint(kind: JointKind.rod, other: b, length: 60),
    );
    world.step(0.016);
    final p = world.componentsOf<Position>();
    expect(p.get(a)!.x, closeTo(20, 1e-9));
    expect(p.get(b)!.x, closeTo(80, 1e-9));
  });

  test('without a Velocity a rod still corrects positions', () {
    final world = _world();
    final a = world.spawn();
    world.componentsOf<Position>().set(a, Position(0, 0));
    world.componentsOf<Joint>().set(
      a,
      Joint(kind: JointKind.rod, anchorX: 100, anchorY: 0, length: 40),
    );
    world.step(0.016);
    expect(world.componentsOf<Position>().get(a)!.x, closeTo(60, 1e-9));
  });

  test('stretching past breakDistance snaps the joint and says so', () {
    final world = _world();
    final a = _body(world, 0, 0);
    final b = _body(world, 500, 0);
    final broken = <JointBroken>[];
    world.events.on<JointBroken>(broken.add);
    world.componentsOf<Joint>().set(
      a,
      Joint(other: b, length: 50, breakDistance: 200),
    );
    world.step(0.016);
    expect(world.componentsOf<Joint>().has(a), isFalse);
    expect((broken.single.entity, broken.single.other), (a, b));
  });

  test('a destroyed far end leaves the joint inert instead of crashing', () {
    final world = _world();
    final a = _body(world, 0, 0);
    final b = _body(world, 100, 0);
    world.componentsOf<Joint>().set(a, Joint(other: b, length: 50));
    world.destroy(b);
    world.step(0.016);
    expect(world.componentsOf<Velocity>().get(a)!.x, 0);
  });

  test('JSON round-trips, including the optional other end', () {
    final j = Joint(
      kind: JointKind.rope,
      other: 7,
      length: 33,
      stiffness: 12,
      damping: 2,
      breakDistance: 90,
    );
    final back = Joint.fromJson(j.toJson());
    expect(
      (back.kind, back.other, back.length, back.breakDistance),
      (JointKind.rope, 7, 33, 90),
    );
    expect(Joint.fromJson({'kind': 'nonsense'}).kind, JointKind.spring);
    expect(Joint.fromJson(Joint(anchorX: 5).toJson()).other, isNull);
  });

  test('time scale slows the solve with the rest of the simulation', () {
    final world = _world();
    final a = _body(world, 0, 0);
    final b = _body(world, 100, 0);
    world.componentsOf<Joint>().set(a, Joint(other: b, length: 50, damping: 0));
    world.timeScale = 0;
    world.step(0.5);
    expect(world.componentsOf<Velocity>().get(a)!.x, 0);
  });
}
