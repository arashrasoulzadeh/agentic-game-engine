import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  return world;
}

void main() {
  test('hitTestButton finds a Button entity whose Collider contains the point', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(100, 100));
    world.storeOf<Collider>().set(id, Collider(20));
    world.storeOf<Button>().set(id, Button('play'));

    expect(hitTestButton(world, 105, 95), id);
  });

  test('hitTestButton returns null outside every button\'s radius', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(100, 100));
    world.storeOf<Collider>().set(id, Collider(20));
    world.storeOf<Button>().set(id, Button('play'));

    expect(hitTestButton(world, 200, 200), isNull);
  });

  test('hitTestButton ignores a Button entity missing Position or Collider', () {
    final world = _buildWorld();
    final noPosition = world.spawn();
    world.storeOf<Collider>().set(noPosition, Collider(999));
    world.storeOf<Button>().set(noPosition, Button('play'));

    expect(hitTestButton(world, 0, 0), isNull);
  });

  test('hitTestButton prefers the most-recently-spawned overlapping button', () {
    final world = _buildWorld();
    final under = world.spawn();
    world.storeOf<Position>().set(under, Position(50, 50));
    world.storeOf<Collider>().set(under, Collider(100));
    world.storeOf<Button>().set(under, Button('under'));

    final over = world.spawn();
    world.storeOf<Position>().set(over, Position(50, 50));
    world.storeOf<Collider>().set(over, Collider(100));
    world.storeOf<Button>().set(over, Button('over'));

    expect(hitTestButton(world, 50, 50), over);
  });

  test('Button round-trips through toJson/fromJson', () {
    final decoded = Button.fromJson(Button('quit').toJson());
    expect(decoded.actionId, 'quit');
  });

  test('ButtonHitBox round-trips through toJson/fromJson', () {
    final decoded = ButtonHitBox.fromJson(ButtonHitBox(220, 64).toJson());
    expect(decoded.width, 220);
    expect(decoded.height, 64);
  });

  group('ButtonHitBox rectangular hit-testing', () {
    test('a point inside the rectangle but outside an equivalent circle still hits', () {
      final world = _buildWorld();
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(100, 100));
      world.storeOf<ButtonHitBox>().set(id, ButtonHitBox(220, 64)); // wide, short
      world.storeOf<Button>().set(id, Button('play'));

      // 95px right of center: inside the 220-wide box (half-width 110),
      // but well outside a circle sized to the short axis (radius 32).
      expect(hitTestButton(world, 195, 100), id);
    });

    test('a point outside the rectangle on the long axis misses', () {
      final world = _buildWorld();
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(100, 100));
      world.storeOf<ButtonHitBox>().set(id, ButtonHitBox(220, 64));
      world.storeOf<Button>().set(id, Button('play'));

      expect(hitTestButton(world, 100 + 111, 100), isNull);
    });

    test('ButtonHitBox takes priority over a Collider on the same entity', () {
      final world = _buildWorld();
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Collider>().set(id, Collider(999)); // would hit almost anywhere
      world.storeOf<ButtonHitBox>().set(id, ButtonHitBox(10, 10)); // tiny
      world.storeOf<Button>().set(id, Button('play'));

      expect(hitTestButton(world, 500, 500), isNull,
          reason: 'the tiny ButtonHitBox should be checked, not the huge Collider');
      expect(hitTestButton(world, 0, 0), id);
    });

    test('a button with neither ButtonHitBox nor Collider is never hit', () {
      final world = _buildWorld();
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Button>().set(id, Button('play'));

      expect(hitTestButton(world, 0, 0), isNull);
    });
  });
}
