import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _world() {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  return w;
}

void main() {
  group('EntityManager.ensureAlive / World.setTick', () {
    test('creates the exact id, keeps skipped ids reusable, is idempotent', () {
      final m = EntityManager();
      m.ensureAlive(3);
      expect(m.isAlive(3), isTrue);
      expect(m.count, 1);
      m.ensureAlive(3);
      expect(m.count, 1);
      final next = {m.create(), m.create(), m.create()};
      expect(next, {0, 1, 2});
      expect(m.create(), 4);
    });

    test('revives a freed id without duplicating it in the free list', () {
      final m = EntityManager();
      final a = m.create();
      m.create();
      m.destroy(a);
      m.ensureAlive(a);
      expect(m.isAlive(a), isTrue);
      expect(m.create(), 2);
    });

    test('setTick overrides the counter', () {
      final w = _world();
      w.setTick(41);
      w.step(0.1);
      expect(w.tick, 42);
    });
  });

  group('WorldSnapshot', () {
    test('capture is a deep copy: later changes do not alter it', () {
      final w = _world();
      final e = w.spawn();
      w.storeOf<Position>().set(e, Position(1, 2));
      final snap = WorldSnapshot.capture(w);
      w.storeOf<Position>().get(e)!.x = 99;
      expect(snap.entities[e]!['position']['x'], 1);
    });

    test(
      'restoreInto brings back moved, destroyed and added entities with original ids',
      () {
        final w = _world();
        final a = w.spawn();
        final b = w.spawn();
        w.storeOf<Position>().set(a, Position(1, 1));
        w.storeOf<Position>().set(b, Position(2, 2));
        w.step(0.1);
        final snap = WorldSnapshot.capture(w);

        w.storeOf<Position>().get(a)!.x = 50;
        final c = w
            .spawn(); // spawned before the destroy, so it cannot reuse b's id
        w.storeOf<Velocity>().set(c, Velocity(1, 1));
        w.destroy(b);
        w.step(0.1);

        snap.restoreInto(w);
        expect(w.tick, snap.tick);
        expect(w.storeOf<Position>().get(a)!.x, 1);
        expect(w.entities.isAlive(b), isTrue);
        expect(w.storeOf<Position>().get(b)!.y, 2);
        expect(w.entities.isAlive(c), isFalse);
        expect(w.storeOf<Velocity>().has(c), isFalse);
      },
    );

    test('restore removes a component that was added after the snapshot', () {
      final w = _world();
      final e = w.spawn();
      w.storeOf<Position>().set(e, Position(0, 0));
      final snap = WorldSnapshot.capture(w);
      w.storeOf<Velocity>().set(e, Velocity(1, 0));
      snap.restoreInto(w);
      expect(w.storeOf<Velocity>().has(e), isFalse);
    });

    test('unchanged entities are not recreated', () {
      final w = _world();
      final e = w.spawn();
      w.storeOf<Position>().set(e, Position(1, 1));
      final instance = w.storeOf<Position>().get(e);
      WorldSnapshot.capture(w).restoreInto(w);
      expect(identical(w.storeOf<Position>().get(e), instance), isTrue);
    });

    test('JSON round trip', () {
      final w = _world();
      w.storeOf<Position>().set(w.spawn(), Position(3, 4));
      final snap = WorldSnapshot.capture(w);
      final back = WorldSnapshot.fromJson(snap.toJson());
      expect(back.tick, snap.tick);
      expect(back.entities[0]!['position']['y'], 4);
    });
  });

  group('WorldDelta', () {
    WorldSnapshot snap(int tick, Map<int, double> xs) => WorldSnapshot(tick, {
      for (final e in xs.entries)
        e.key: {
          'position': {'x': e.value, 'y': 0.0},
        },
    });

    test('lists only changed, new and removed entities', () {
      final d = WorldDelta.between(
        snap(1, {0: 1, 1: 2, 2: 3}),
        snap(2, {0: 1, 1: 9, 3: 4}),
      );
      expect(d.changed.keys.toSet(), {1, 3});
      expect(d.removed, [2]);
      expect(d.baseTick, 1);
      expect(d.tick, 2);
      expect(d.isEmpty, isFalse);
    });

    test(
      'applyTo reconstructs the target exactly; identical snapshots give an empty delta',
      () {
        final a = snap(1, {0: 1, 1: 2});
        final b = snap(2, {0: 5, 2: 7});
        expect(WorldDelta.between(a, b).applyTo(a).entities, b.entities);
        expect(WorldDelta.between(a, a).isEmpty, isTrue);
      },
    );

    test('applyTo refuses the wrong baseline', () {
      final d = WorldDelta.between(snap(1, {0: 1}), snap(2, {0: 2}));
      expect(() => d.applyTo(snap(5, {0: 1})), throwsStateError);
    });

    test('JSON round trip', () {
      final d = WorldDelta.between(snap(1, {0: 1, 1: 1}), snap(2, {0: 2}));
      final back = WorldDelta.fromJson(d.toJson());
      expect(back.removed, [1]);
      expect(back.changed[0]!['position']['x'], 2);
      expect(back.baseTick, 1);
    });
  });
}
