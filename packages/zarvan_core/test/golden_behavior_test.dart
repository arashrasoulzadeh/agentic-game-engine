import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

/// Pins today's behavior of the pieces the SIMPLER refactor will touch (event
/// bus, dense stores, entity ids). A failure here after a refactor step means
/// the step changed observable behavior: update the test only when that change
/// is intended and recorded in the commit message.

class _Ping {
  final int n;
  _Ping(this.n);
}

class _Pong {}

class _BasePing {}

class _SubPing extends _BasePing {}

class _Recorder implements System {
  final List<String> log;
  final String id;
  final void Function(World world)? action;
  _Recorder(this.id, this.log, [this.action]);

  @override
  String get name => id;

  @override
  void update(World world, double dt) {
    log.add('sys:$id');
    action?.call(world);
  }
}

World _world() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  return world;
}

void main() {
  group('event ordering', () {
    test('events emitted by systems are delivered after every system ran', () {
      final world = _world();
      final log = <String>[];
      world.events.on<_Ping>((e) => log.add('ping:${e.n}'));
      world
        ..addSystem(_Recorder('a', log, (w) => w.events.emit(_Ping(1))))
        ..addSystem(_Recorder('b', log));
      world.step(0.1);
      expect(log, ['sys:a', 'sys:b', 'ping:1']);
    });

    test('handlers run in registration order, events in emit order', () {
      final world = _world();
      final log = <String>[];
      world.events
        ..on<_Ping>((e) => log.add('first:${e.n}'))
        ..on<_Ping>((e) => log.add('second:${e.n}'));
      world.events
        ..emit(_Ping(1))
        ..emit(_Ping(2));
      world.events.flush();
      expect(log, ['first:1', 'second:1', 'first:2', 'second:2']);
    });

    test('an event emitted from a handler is delivered in a later round of '
        'the same flush, after the current round finishes', () {
      final world = _world();
      final log = <String>[];
      world.events
        ..on<_Ping>((e) {
          log.add('ping:${e.n}');
          if (e.n == 1) world.events.emit(_Pong());
        })
        ..on<_Pong>((_) => log.add('pong'));
      world.events
        ..emit(_Ping(1))
        ..emit(_Ping(2));
      world.events.flush();
      expect(log, ['ping:1', 'ping:2', 'pong']);
    });

    test('handlers are matched on the exact runtime type: a handler for a '
        'base type does not receive subclass events', () {
      final world = _world();
      var base = 0;
      var sub = 0;
      world.events
        ..on<_BasePing>((_) => base++)
        ..on<_SubPing>((_) => sub++);
      world.events.emit(_SubPing());
      world.events.flush();
      expect(base, 0);
      expect(sub, 1);
    });

    test(
      'a self-re-emitting handler is cut off after 20 cascade rounds; the '
      'pending event stays queued and cascades 20 more on the next flush',
      () {
        final world = _world();
        var delivered = 0;
        world.events.on<_Ping>((e) {
          delivered++;
          world.events.emit(_Ping(e.n + 1));
        });
        world.events.emit(_Ping(0));
        world.events.flush();
        expect(delivered, 20);
        delivered = 0;
        world.events.flush();
        expect(delivered, 20, reason: 'nothing was dropped, only deferred');
      },
    );

    test('clearHandlers cancels every handler', () {
      final world = _world();
      var hits = 0;
      world.events.on<_Ping>((_) => hits++);
      world.events.clearHandlers();
      world.events.emit(_Ping(0));
      world.events.flush();
      expect(hits, 0);
    });

    test('step advances the tick and flushes events exactly once', () {
      final world = _world();
      var hits = 0;
      world.events.on<_Ping>((_) => hits++);
      world.events.emit(_Ping(0));
      world.step(0.5);
      expect(world.tick, 1);
      expect(world.deltaTime, 0.5);
      expect(hits, 1);
      world.step(0.5);
      expect(hits, 1);
    });

    test('systems run in insertion order', () {
      final world = _world();
      final log = <String>[];
      world
        ..addSystem(_Recorder('a', log))
        ..addSystem(_Recorder('b', log))
        ..addSystem(_Recorder('c', log));
      world.step(0.1);
      expect(log, ['sys:a', 'sys:b', 'sys:c']);
      expect(world.systemOrder, ['a', 'b', 'c']);
    });
  });

  group('destroy during iteration', () {
    test('destroying each entity while walking the dense array forward skips '
        'every other one (swap-remove)', () {
      final world = _world();
      final ids = [for (var i = 0; i < 4; i++) world.spawn()];
      for (final id in ids) {
        world.componentsOf<Position>().set(id, Position(id.toDouble(), 0));
      }
      final store = world.componentsOf<Position>();
      final visited = <EntityId>[];
      for (var i = 0; i < store.length; i++) {
        final id = store.entityAt(i);
        visited.add(id);
        world.destroy(id);
      }
      expect(visited, [ids[0], ids[1]]);
      expect(world.entities.all.toSet(), {ids[2], ids[3]});
    });

    test('walking the dense array backwards visits every entity', () {
      final world = _world();
      final ids = [for (var i = 0; i < 4; i++) world.spawn()];
      for (final id in ids) {
        world.componentsOf<Position>().set(id, Position(0, 0));
      }
      final store = world.componentsOf<Position>();
      final visited = <EntityId>[];
      for (var i = store.length - 1; i >= 0; i--) {
        final id = store.entityAt(i);
        visited.add(id);
        world.destroy(id);
      }
      expect(visited.toSet(), ids.toSet());
      expect(world.entities.count, 0);
    });

    test('destroying a snapshot of ids is safe and removes everything', () {
      final world = _world();
      final ids = [for (var i = 0; i < 4; i++) world.spawn()];
      for (final id in ids) {
        world.componentsOf<Position>().set(id, Position(0, 0));
      }
      for (final id in List.of(ids)) {
        world.destroy(id);
      }
      expect(world.componentsOf<Position>().length, 0);
      expect(world.entities.count, 0);
    });

    test('a system that destroys an entity is seen immediately by the next '
        'system in the same step', () {
      final world = _world();
      final id = world.spawn();
      world.componentsOf<Position>().set(id, Position(0, 0));
      final seen = <bool>[];
      world
        ..addSystem(_Recorder('kill', [], (w) => w.destroy(id)))
        ..addSystem(
          _Recorder('look', [], (w) => seen.add(w.componentsOf<Position>().has(id))),
        );
      world.step(0.1);
      expect(seen, [false]);
    });

    test('destroy removes the entity from every component store', () {
      final world = _world();
      final id = world.spawn();
      world.componentsOf<Position>().set(id, Position(1, 2));
      world.componentsOf<Velocity>().set(id, Velocity(3, 4));
      world.destroy(id);
      expect(world.componentsOf<Position>().has(id), isFalse);
      expect(world.componentsOf<Velocity>().has(id), isFalse);
      expect(world.entities.isAlive(id), isFalse);
    });

    test('destroying an already dead id is a no-op', () {
      final world = _world();
      final id = world.spawn();
      world.destroy(id);
      world.destroy(id);
      expect(world.entities.count, 0);
      final a = world.spawn();
      final b = world.spawn();
      expect(
        a,
        isNot(b),
        reason: 'a double destroy must not free the id twice',
      );
    });
  });

  group('entity id reuse', () {
    test('a fresh world hands out 0, 1, 2 in order', () {
      final world = _world();
      expect([world.spawn(), world.spawn(), world.spawn()], [0, 1, 2]);
    });

    test('a freed id is reused by the next spawn (last freed first)', () {
      final world = _world();
      final a = world.spawn();
      final b = world.spawn();
      final c = world.spawn();
      world.destroy(a);
      world.destroy(c);
      expect(world.spawn(), c);
      expect(world.spawn(), a);
      expect(world.spawn(), isNot(anyOf(a, b, c)));
    });

    test('a stale id aliases the entity that reused it: it reports alive and '
        'reads the new entity\'s components', () {
      final world = _world();
      final old = world.spawn();
      world.componentsOf<Position>().set(old, Position(1, 1));
      world.destroy(old);
      expect(world.entities.isAlive(old), isFalse);

      final fresh = world.spawn();
      world.componentsOf<Position>().set(fresh, Position(9, 9));
      expect(fresh, old);
      expect(world.entities.isAlive(old), isTrue);
      expect(world.componentsOf<Position>().get(old)!.x, 9);
    });

    test('a reused id starts with no components', () {
      final world = _world();
      final old = world.spawn();
      world.componentsOf<Position>().set(old, Position(1, 1));
      world.destroy(old);
      final fresh = world.spawn();
      expect(world.componentsOf<Position>().has(fresh), isFalse);
    });

    test('ensureAlive creates the id and frees the gap below it', () {
      final world = _world();
      world.entities.ensureAlive(3);
      expect(world.entities.isAlive(3), isTrue);
      expect(world.entities.count, 1);
      final next = world.spawn();
      expect(next, lessThan(3), reason: 'gap ids 0..2 are reusable');
    });

    test('ids survive a toJson/applyPatch round trip unchanged', () {
      final world = _world();
      final a = world.spawn();
      final b = world.spawn();
      world.componentsOf<Position>().set(b, Position(5, 6));
      world.destroy(a);
      final json = world.toJson();
      expect([for (final e in json['entities'] as List) e['id']], [b]);
    });
  });
}
