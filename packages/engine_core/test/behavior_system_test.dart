import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _TestBehavior implements Behavior {
  @override
  Action decide(WorldView view, EntityId self) => const NoOpAction();
}

class _TestSystem implements System {
  bool updated = false;
  World? lastWorld;
  double? lastDt;

  @override
  String get name => 'testSystem';

  @override
  void update(World world, double dt) {
    updated = true;
    lastWorld = world;
    lastDt = dt;
  }
}

class _NamedSystem implements System {
  @override
  String get name => 'myCustomSystem';
  @override
  void update(World world, double dt) {}
}

void main() {
  group('Behavior (base)', () {
    test('decide returns NoOpAction by default for unimplemented', () {
      final behavior = _TestBehavior();
      final world = World(width: 10, height: 10);
      registerCoreComponents(world);
      final view = WorldView(world);
      final action = behavior.decide(view, 0);
      expect(action, isA<NoOpAction>());
    });
  });

  group('System (base)', () {
    test('update is called with world and dt', () {
      final system = _TestSystem();
      final world = World(width: 10, height: 10);
      registerCoreComponents(world);

      system.update(world, 0.016);
      expect(system.updated, isTrue);
      expect(system.lastWorld, same(world));
      expect(system.lastDt, 0.016);
    });

    test('name returns identifying string', () {
      expect(_NamedSystem().name, 'myCustomSystem');
    });
  });

  group('NoOpAction', () {
    test('apply does nothing', () {
      final world = World(width: 10, height: 10);
      registerCoreComponents(world);
      const NoOpAction().apply(world);
    });
  });
}