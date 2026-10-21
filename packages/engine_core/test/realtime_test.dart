import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridNavigator _nav({int size = 20, Set<(int, int)> walls = const {}}) =>
    GridNavigator(
      cols: size,
      rows: size,
      terrainCost: (c, r) => walls.contains((c, r)) ? null : 1,
    );

/// A real-time world: no TurnState.
({World world, FlowFieldCache cache}) _game({
  int size = 20,
  Set<(int, int)> walls = const {},
  bool fog = false,
}) {
  final w = World(width: size.toDouble(), height: size.toDouble());
  registerCoreComponents(w);
  if (fog) {
    w.storeOf<FogOfWar>().set(w.spawn(), FogOfWar(size, size));
    w.addSystem(VisionSystem());
  }
  final cache = FlowFieldCache(_nav(size: size, walls: walls));
  w.addSystem(RealtimeOrderSystem(fields: cache));
  return (world: w, cache: cache);
}

GridPosition _at(World w, EntityId e) => w.storeOf<GridPosition>().get(e)!;

void _run(World w, double seconds, {double dt = 0.05}) {
  final steps = (seconds / dt).round();
  for (var i = 0; i < steps; i++) {
    w.step(dt);
  }
}

void main() {
  group('orders without a turn clock', () {
    test('any unit with a team can be ordered; one without a team cannot', () {
      final g = _game();
      final u = spawnRealtimeUnit(g.world, team: 'red', col: 0, row: 0);
      expect(submitOrder(g.world, u, const MoveOrder(3, 3)), isTrue);
      final stray = g.world.spawn();
      expect(submitOrder(g.world, stray, const MoveOrder(1, 1)), isFalse);
    });

    test('selection and commands take an explicit team', () {
      final g = _game();
      final red = spawnRealtimeUnit(g.world, team: 'red', col: 2, row: 2);
      final blue = spawnRealtimeUnit(g.world, team: 'blue', col: 5, row: 5);
      expect(
        selectAtCell(g.world, 2, 2),
        isNull,
        reason: 'no clock and no team: nothing is selectable',
      );
      expect(selectInBox(g.world, 0, 0, 9, 9), 0);
      expect(
        selectAtCell(g.world, 5, 5, team: 'red'),
        isNull,
        reason: 'an enemy is not selectable',
      );
      expect(selectAtCell(g.world, 2, 2, team: 'red'), red);
      expect(commandSelected(g.world, 9, 9), 0, reason: 'no clock and no team');
      expect(commandSelected(g.world, 5, 5, team: 'red'), 1);
      expect(
        (g.world.storeOf<OrderQueue>().get(red)!.orders.single as AttackOrder)
            .target,
        blue,
      );
      expect(selectInBox(g.world, 0, 0, 9, 9, team: 'blue'), 1);
    });
  });

  group('movement', () {
    test('moves at its speed: 2 cells/s covers 6 cells in 3 s, no faster', () {
      final g = _game();
      final u = spawnRealtimeUnit(
        g.world,
        team: 'red',
        col: 0,
        row: 0,
        speed: 2,
      );
      submitOrder(g.world, u, const MoveOrder(6, 0));
      _run(g.world, 1.5);
      expect(_at(g.world, u).col, 3);
      _run(g.world, 1.5);
      expect(_at(g.world, u).col, 6);
      expect(g.world.storeOf<OrderQueue>().get(u)!.orders, isEmpty);
    });

    test(
      'a slow unit still averages its speed because progress carries over',
      () {
        final g = _game();
        final u = spawnRealtimeUnit(
          g.world,
          team: 'red',
          col: 0,
          row: 0,
          speed: 0.7,
        );
        submitOrder(g.world, u, const MoveOrder(15, 0));
        _run(g.world, 10, dt: 0.1);
        expect(_at(g.world, u).col, 7);
      },
    );

    test('routes around walls', () {
      final g = _game(walls: {for (var r = 0; r < 10; r++) (5, r)});
      final u = spawnRealtimeUnit(
        g.world,
        team: 'red',
        col: 2,
        row: 2,
        speed: 10,
      );
      submitOrder(g.world, u, const MoveOrder(8, 2));
      _run(g.world, 4);
      expect((_at(g.world, u).col, _at(g.world, u).row), (8, 2));
    });

    test('an unreachable destination fails the order with blocked', () {
      final g = _game(walls: {(5, 5)});
      final u = spawnRealtimeUnit(g.world, team: 'red', col: 0, row: 0);
      final failed = <OrderFailedEvent>[];
      g.world.events.on<OrderFailedEvent>(failed.add);
      submitOrder(g.world, u, const MoveOrder(5, 5));
      _run(g.world, 0.2);
      expect(failed.single.reason, OrderFailure.blocked);
      expect(g.world.storeOf<OrderQueue>().get(u)!.orders, isEmpty);
    });

    test(
      'a group sent to one cell shares a single flow field and does not stack',
      () {
        final g = _game(size: 30);
        final units = [
          for (var i = 0; i < 40; i++)
            spawnRealtimeUnit(
              g.world,
              team: 'red',
              col: i % 8,
              row: i ~/ 8,
              speed: 8,
            ),
        ];
        for (final u in units) {
          submitOrder(g.world, u, const MoveOrder(25, 25));
        }
        _run(g.world, 12);
        expect(g.cache.builds, 1);
        final cells = {
          for (final u in units) (_at(g.world, u).col, _at(g.world, u).row),
        };
        expect(cells.length, 40, reason: 'no two units share a cell');
        for (final u in units) {
          expect(
            _at(g.world, u).chebyshev(GridPosition(25, 25)),
            lessThanOrEqualTo(6),
          );
        }
      },
    );

    test(
      'a unit boxed in waits instead of overlapping, then moves when freed',
      () {
        final g = _game(size: 6);
        final w = g.world;
        final blocker = spawnRealtimeUnit(
          w,
          team: 'red',
          col: 1,
          row: 0,
          speed: 0,
        );
        final u = spawnRealtimeUnit(w, team: 'red', col: 0, row: 0, speed: 20);
        // Surround the mover so every improving step is occupied.
        final others = [
          spawnRealtimeUnit(w, team: 'red', col: 0, row: 1, speed: 0),
          spawnRealtimeUnit(w, team: 'red', col: 1, row: 1, speed: 0),
        ];
        submitOrder(w, u, const MoveOrder(5, 0));
        _run(w, 0.5);
        expect((_at(w, u).col, _at(w, u).row), (0, 0));
        expect(
          w.storeOf<RealtimeStats>().get(u)!.moveProgress,
          lessThanOrEqualTo(1),
        );
        for (final o in [blocker, ...others]) {
          w.destroy(o);
        }
        _run(w, 1);
        expect(_at(w, u).col, 5);
      },
    );
  });

  group('combat', () {
    test(
      'an attacker walks to range, then hits on its cooldown until the target dies',
      () {
        final g = _game();
        final w = g.world;
        final a = spawnRealtimeUnit(
          w,
          team: 'red',
          col: 0,
          row: 0,
          speed: 4,
          attackInterval: 1,
          attack: 4,
        );
        final b = spawnRealtimeUnit(
          w,
          team: 'blue',
          col: 6,
          row: 0,
          speed: 0,
          maxHp: 10,
        );
        final hits = <double>[];
        var t = 0.0;
        w.events.on<UnitDamagedEvent>((e) => hits.add(t));
        submitOrder(w, a, AttackOrder(b));
        for (var i = 0; i < 100 && w.entities.isAlive(b); i++) {
          t += 0.05;
          w.step(0.05);
        }
        expect(w.entities.isAlive(b), isFalse);
        expect(hits, hasLength(3), reason: '10 hp, 4 damage per hit');
        expect(
          hits[1] - hits[0],
          closeTo(1.0, 0.06),
          reason: 'one hit per attackInterval',
        );
        expect(hits[2] - hits[1], closeTo(1.0, 0.06));
        expect(
          _at(w, a).chebyshev(GridPosition(6, 0)),
          1,
          reason: 'stopped at melee range',
        );
        expect(w.storeOf<OrderQueue>().get(a)!.orders, isEmpty);
      },
    );

    test('it chases a moving target', () {
      final g = _game();
      final w = g.world;
      final a = spawnRealtimeUnit(
        w,
        team: 'red',
        col: 0,
        row: 0,
        speed: 6,
        attack: 100,
      );
      final b = spawnRealtimeUnit(
        w,
        team: 'blue',
        col: 4,
        row: 0,
        speed: 2,
        maxHp: 10,
      );
      submitOrder(w, b, const MoveOrder(15, 15));
      submitOrder(w, a, AttackOrder(b));
      _run(w, 6);
      expect(w.entities.isAlive(b), isFalse);
    });

    test(
      'ranged units shoot from their AttackProfile range without closing in',
      () {
        final g = _game();
        final w = g.world;
        final archer = spawnRealtimeUnit(
          w,
          team: 'red',
          col: 0,
          row: 0,
          speed: 3,
          attack: 5,
        );
        w.storeOf<AttackProfile>().set(archer, AttackProfile(range: 4));
        final target = spawnRealtimeUnit(
          w,
          team: 'blue',
          col: 4,
          row: 0,
          speed: 0,
          maxHp: 50,
        );
        submitOrder(w, archer, AttackOrder(target));
        _run(w, 0.2);
        expect(w.storeOf<UnitStats>().get(target)!.hp, 45);
        expect(_at(w, archer).col, 0);
      },
    );

    test('friendly fire and dead targets: invalid vs silently done', () {
      final g = _game();
      final w = g.world;
      final a = spawnRealtimeUnit(w, team: 'red', col: 0, row: 0);
      final friend = spawnRealtimeUnit(w, team: 'red', col: 1, row: 0);
      final foe = spawnRealtimeUnit(w, team: 'blue', col: 5, row: 5);
      final failed = <OrderFailedEvent>[];
      w.events.on<OrderFailedEvent>(failed.add);
      submitOrder(w, a, AttackOrder(friend));
      _run(w, 0.1);
      expect(failed.single.reason, OrderFailure.invalidTarget);

      failed.clear();
      submitOrder(w, a, AttackOrder(foe));
      w.destroy(foe);
      _run(w, 0.1);
      expect(failed, isEmpty);
      expect(w.storeOf<OrderQueue>().get(a)!.orders, isEmpty);
    });

    test('fog: cannot attack what the team cannot see', () {
      final g = _game(fog: true);
      final w = g.world;
      final a = spawnRealtimeUnit(w, team: 'red', col: 0, row: 0);
      w.storeOf<Vision>().set(a, Vision(1));
      final foe = spawnRealtimeUnit(w, team: 'blue', col: 10, row: 10);
      final failed = <OrderFailedEvent>[];
      w.events.on<OrderFailedEvent>(failed.add);
      submitOrder(w, a, AttackOrder(foe));
      _run(w, 0.2);
      expect(failed.single.reason, OrderFailure.invalidTarget);
    });

    test('turn-only orders are rejected in real time', () {
      final g = _game();
      final u = spawnRealtimeUnit(g.world, team: 'red', col: 0, row: 0);
      final failed = <OrderFailedEvent>[];
      g.world.events.on<OrderFailedEvent>(failed.add);
      submitOrder(g.world, u, const DefendOrder());
      _run(g.world, 0.1);
      expect(failed.single.order, isA<DefendOrder>());
    });

    test('orders run in sequence', () {
      final g = _game();
      final u = spawnRealtimeUnit(
        g.world,
        team: 'red',
        col: 0,
        row: 0,
        speed: 10,
      );
      submitOrder(g.world, u, const MoveOrder(3, 0));
      submitOrder(g.world, u, const MoveOrder(3, 4));
      _run(g.world, 2);
      expect((_at(g.world, u).col, _at(g.world, u).row), (3, 4));
    });
  });

  group('LastTeamStandingSystem', () {
    test(
      'declares the survivor once, and not before a second team has been seen',
      () {
        final w = World(width: 5, height: 5);
        registerCoreComponents(w);
        final sys = LastTeamStandingSystem();
        w.addSystem(sys);
        final victories = <VictoryEvent>[];
        w.events.on<VictoryEvent>(victories.add);
        final a = spawnRealtimeUnit(w, team: 'red', col: 0, row: 0);
        w.step(0.1);
        expect(sys.winner, isNull, reason: 'only one team has ever existed');
        final b = spawnRealtimeUnit(w, team: 'blue', col: 1, row: 1);
        w.step(0.1);
        expect(sys.winner, isNull);
        w.destroy(b);
        w.step(0.1);
        w.step(0.1);
        expect(sys.winner, 'red');
        expect(victories.single.team, 'red');
        expect(a, isNonNegative);
      },
    );
  });

  group('determinism (lockstep)', () {
    // Two independent worlds fed the same orders and the same fixed dt must end
    // identical - the property lockstep multiplayer and replays rely on.
    World battle() {
      final g = _game(size: 24, walls: {for (var r = 4; r < 20; r++) (12, r)});
      final w = g.world;
      w.addSystem(LastTeamStandingSystem());
      installCombat(w);
      final reds = [
        for (var i = 0; i < 15; i++)
          spawnRealtimeUnit(
            w,
            team: 'red',
            col: 1 + i % 3,
            row: 2 + i ~/ 3,
            speed: 3,
            attack: 2,
          ),
      ];
      final blues = [
        for (var i = 0; i < 15; i++)
          spawnRealtimeUnit(
            w,
            team: 'blue',
            col: 20 + i % 3,
            row: 2 + i ~/ 3,
            speed: 2.5,
            attack: 2,
          ),
      ];
      for (var i = 0; i < reds.length; i++) {
        submitOrder(w, reds[i], AttackOrder(blues[(i * 7) % blues.length]));
        submitOrder(w, blues[i], AttackOrder(reds[(i * 5) % reds.length]));
      }
      return w;
    }

    String fingerprint(World w) =>
        jsonEncode(WorldSnapshot.capture(w).toJson());

    test(
      'identical worlds stay identical over hundreds of ticks of battle',
      () {
        final a = battle(), b = battle();
        for (var i = 0; i < 400; i++) {
          a.step(1 / 20);
          b.step(1 / 20);
        }
        expect(fingerprint(a), fingerprint(b));
        expect(
          a.storeOf<UnitStats>().length,
          lessThan(30),
          reason: 'fighting actually happened',
        );
      },
    );

    test(
      'restoring a snapshot mid-battle and replaying reaches the same end state',
      () {
        final a = battle();
        for (var i = 0; i < 100; i++) {
          a.step(1 / 20);
        }
        final midpoint = WorldSnapshot.capture(a);
        for (var i = 0; i < 100; i++) {
          a.step(1 / 20);
        }

        final b = battle();
        midpoint.restoreInto(b);
        for (var i = 0; i < 100; i++) {
          b.step(1 / 20);
        }
        expect(fingerprint(b), fingerprint(a));
      },
    );
  });

  test('RealtimeStats round-trips JSON with defaults', () {
    final back = RealtimeStats.fromJson(
      RealtimeStats(
        speed: 3,
        attackInterval: 0.5,
        moveProgress: 0.25,
        cooldown: 0.1,
      ).toJson(),
    );
    expect(
      (back.speed, back.attackInterval, back.moveProgress, back.cooldown),
      (3, 0.5, 0.25, 0.1),
    );
    final d = RealtimeStats.fromJson({});
    expect((d.speed, d.attackInterval), (2, 1));
  });
}
