import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridNavigator _nav() => GridNavigator(cols: 10, rows: 10, terrainCost: (c, r) => 1);

const _soldier = {
  'unitStats': {'maxHp': 12, 'hp': 12, 'attack': 4, 'defense': 1},
  'realtimeStats': {'speed': 3.0, 'attackInterval': 1.0},
};

({World world, EntityId barracks, Treasury treasury}) _setup({
  Map<String, int> gold = const {'gold': 100},
  Map<String, int> cost = const {'gold': 30},
  double seconds = 2,
}) {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  w.addSystem(ProductionSystem(_nav()));
  final treasury = Treasury('red', amounts: {...gold});
  w.storeOf<Treasury>().set(w.spawn(), treasury);
  final b = w.spawn();
  w.storeOf<Team>().set(b, Team('red'));
  w.storeOf<GridPosition>().set(b, GridPosition(5, 5));
  w.storeOf<Producer>().set(b, Producer(cost: {...cost}, seconds: seconds, template: _soldier));
  return (world: w, barracks: b, treasury: treasury);
}

void _run(World w, double seconds, {double dt = 0.1}) {
  for (var i = 0; i < (seconds / dt).round(); i++) {
    w.step(dt);
  }
}

void main() {
  group('Treasury', () {
    test('spend is all-or-nothing and canAfford agrees', () {
      final t = Treasury('red', amounts: {'gold': 50, 'wood': 10});
      expect(t.canAfford({'gold': 50, 'wood': 10}), isTrue);
      expect(t.canAfford({'gold': 50, 'wood': 11}), isFalse);
      expect(t.spend({'gold': 20, 'wood': 99}), isFalse);
      expect((t.of('gold'), t.of('wood')), (50, 10), reason: 'a failed spend takes nothing');
      expect(t.spend({'gold': 20, 'wood': 5}), isTrue);
      expect((t.of('gold'), t.of('wood')), (30, 5));
      expect(t.of('iron'), 0);
      expect(t.canAfford({}), isTrue);
    });

    test('fractional income carries over: 0.5/s yields one every two seconds', () {
      final t = Treasury('red', incomePerSecond: {'gold': 0.5});
      for (var i = 0; i < 4; i++) {
        t.accrue(0.5);
      }
      expect(t.of('gold'), 1);
      for (var i = 0; i < 4; i++) {
        t.accrue(0.5);
      }
      expect(t.of('gold'), 2);
    });

    test('many resources accrue independently', () {
      final t = Treasury('red', incomePerSecond: {'gold': 2.0, 'wood': 0.25});
      for (var i = 0; i < 40; i++) {
        t.accrue(0.1);
      }
      expect((t.of('gold'), t.of('wood')), (8, 1));
    });

    test('JSON round trip, including the fractional carry', () {
      final t = Treasury.fromJson(Treasury('blue',
              amounts: {'gold': 7}, incomePerSecond: {'gold': 1.5}, carry: {'gold': 0.25})
          .toJson());
      expect((t.team, t.of('gold'), t.incomePerSecond['gold'], t.carry['gold']), ('blue', 7, 1.5, 0.25));
      expect(Treasury.fromJson({'team': 'x'}).amounts, isEmpty);
    });
  });

  group('ProductionSystem', () {
    test('pays at the start, builds for its duration, then spawns the unit on the producer\'s team', () {
      final s = _setup();
      final produced = <UnitProducedEvent>[];
      s.world.events.on<UnitProducedEvent>(produced.add);
      expect(queueProduction(s.world, s.barracks), isTrue);

      _run(s.world, 0.1);
      expect(s.treasury.of('gold'), 70, reason: 'paid as soon as it starts');
      expect(produced, isEmpty);
      _run(s.world, 1.7);
      expect(produced, isEmpty, reason: 'still building');
      _run(s.world, 0.4);

      expect(produced, hasLength(1));
      final unit = produced.single.unit;
      expect(s.world.storeOf<Team>().get(unit)!.id, 'red');
      expect(s.world.storeOf<UnitStats>().get(unit)!.attack, 4);
      expect(s.world.storeOf<RealtimeStats>().get(unit)!.speed, 3);
      final at = s.world.storeOf<GridPosition>().get(unit)!;
      expect(at.chebyshev(GridPosition(5, 5)), 1, reason: 'next to the barracks');
      expect(s.world.storeOf<Producer>().get(s.barracks)!.queued, 0);
    });

    test('a queue builds one unit at a time, charging each', () {
      final s = _setup(seconds: 1);
      queueProduction(s.world, s.barracks, 3);
      _run(s.world, 1.05);
      expect(s.world.storeOf<UnitStats>().length, 1);
      _run(s.world, 2.1);
      expect(s.world.storeOf<UnitStats>().length, 3);
      expect(s.treasury.of('gold'), 10);
    });

    test('not enough resources: it stalls, says so once, and resumes when income arrives', () {
      final s = _setup(gold: const {'gold': 10});
      final stalled = <ProductionStalledEvent>[];
      s.world.events.on<ProductionStalledEvent>(stalled.add);
      final produced = <UnitProducedEvent>[];
      s.world.events.on<UnitProducedEvent>(produced.add);
      queueProduction(s.world, s.barracks);
      _run(s.world, 1);
      expect(stalled, hasLength(1), reason: 'announced once, not every tick');
      expect(stalled.single.missing, {'gold': 20});
      expect(s.treasury.of('gold'), 10, reason: 'nothing was taken');

      s.treasury.incomePerSecond['gold'] = 20;
      _run(s.world, 4);
      expect(produced, hasLength(1));
    });

    test('a producer on a team with no treasury never builds, and reports everything missing', () {
      final w = World(width: 10, height: 10);
      registerCoreComponents(w);
      w.addSystem(ProductionSystem(_nav()));
      final b = w.spawn();
      w.storeOf<Team>().set(b, Team('green'));
      w.storeOf<GridPosition>().set(b, GridPosition(2, 2));
      w.storeOf<Producer>().set(b, Producer(cost: {'gold': 5}, seconds: 1, template: _soldier));
      final stalled = <ProductionStalledEvent>[];
      w.events.on<ProductionStalledEvent>(stalled.add);
      queueProduction(w, b);
      _run(w, 2);
      expect(stalled.single.missing, {'gold': 5});
      expect(w.storeOf<UnitStats>().length, 0);
    });

    test('two producers on one treasury compete deterministically, lowest id first', () {
      final s = _setup(gold: const {'gold': 30});
      final second = s.world.spawn();
      s.world.storeOf<Team>().set(second, Team('red'));
      s.world.storeOf<GridPosition>().set(second, GridPosition(8, 8));
      s.world.storeOf<Producer>().set(second, Producer(cost: {'gold': 30}, seconds: 1, template: _soldier));
      queueProduction(s.world, second);
      queueProduction(s.world, s.barracks);
      _run(s.world, 0.1);
      expect(s.world.storeOf<Producer>().get(s.barracks)!.paid, isTrue, reason: 'barracks has the lower id');
      expect(s.world.storeOf<Producer>().get(second)!.paid, isFalse);
    });

    test('a unit waits (finished, unspawned) when there is no room, rather than overlapping', () {
      final tiny = World(width: 2, height: 1);
      registerCoreComponents(tiny);
      tiny.addSystem(ProductionSystem(GridNavigator(cols: 2, rows: 1, terrainCost: (c, r) => 1)));
      tiny.storeOf<Treasury>().set(tiny.spawn(), Treasury('red', amounts: {'gold': 100}));
      final b = tiny.spawn();
      tiny.storeOf<Team>().set(b, Team('red'));
      tiny.storeOf<GridPosition>().set(b, GridPosition(0, 0));
      tiny.storeOf<Producer>().set(b, Producer(cost: {}, seconds: 1, template: _soldier));
      final blocker = tiny.spawn();
      tiny.storeOf<GridPosition>().set(blocker, GridPosition(1, 0));
      queueProduction(tiny, b);
      _run(tiny, 3);
      expect(tiny.storeOf<UnitStats>().length, 0);
      expect(tiny.storeOf<Producer>().get(b)!.queued, 1);

      tiny.destroy(blocker);
      _run(tiny, 0.2);
      expect(tiny.storeOf<UnitStats>().length, 1);
      expect(tiny.storeOf<Producer>().get(b)!.queued, 0);
    });

    test('queueProduction rejects non-producers and non-positive counts', () {
      final s = _setup();
      expect(queueProduction(s.world, s.world.spawn()), isFalse);
      expect(queueProduction(s.world, s.barracks, 0), isFalse);
      expect(queueProduction(s.world, s.barracks, -2), isFalse);
      expect(s.world.storeOf<Producer>().get(s.barracks)!.queued, 0);
    });

    test('produced units are real units: they can be ordered and fight', () {
      final s = _setup(seconds: 0.5);
      final cache = FlowFieldCache(_nav());
      s.world.addSystem(RealtimeOrderSystem(fields: cache));
      queueProduction(s.world, s.barracks);
      final produced = <UnitProducedEvent>[];
      s.world.events.on<UnitProducedEvent>(produced.add);
      _run(s.world, 1);
      final unit = produced.single.unit;
      expect(submitOrder(s.world, unit, const MoveOrder(9, 9)), isTrue);
      _run(s.world, 6);
      expect(s.world.storeOf<GridPosition>().get(unit)!.col, 9);
    });
  });

  test('Producer round-trips JSON, including mid-build state', () {
    final p = Producer.fromJson(Producer(
      cost: {'gold': 3},
      seconds: 4,
      template: _soldier,
      queued: 2,
      progress: 1.5,
      paid: true,
    ).toJson());
    expect((p.cost['gold'], p.seconds, p.queued, p.progress, p.paid), (3, 4, 2, 1.5, true));
    expect(jsonEncode(p.template), jsonEncode(_soldier));
    expect(Producer.fromJson({'seconds': 1}).template, isEmpty);
  });

  test('a world mid-production survives a snapshot round trip and finishes identically', () {
    World build() {
      final s = _setup(seconds: 3);
      queueProduction(s.world, s.barracks, 2);
      return s.world;
    }

    final a = build();
    _run(a, 1.5);
    final snap = WorldSnapshot.capture(a);
    _run(a, 5);

    final b = build();
    snap.restoreInto(b);
    _run(b, 5);
    expect(jsonEncode(WorldSnapshot.capture(b).toJson()), jsonEncode(WorldSnapshot.capture(a).toJson()));
  });

  test('a restored world pays fractional income on the same tick as the original', () {
    World build() {
      final w = World(width: 4, height: 4);
      registerCoreComponents(w);
      w.addSystem(ProductionSystem(_nav()));
      w.storeOf<Treasury>().set(w.spawn(), Treasury('red', incomePerSecond: {'gold': 0.7}));
      return w;
    }

    int gold(World w) => w.storeOf<Treasury>().denseAt(0).of('gold');

    final a = build();
    for (var i = 0; i < 13; i++) {
      a.step(0.1); // 0.91 earned: carries a fraction, no whole unit yet
    }
    final snap = WorldSnapshot.capture(a);
    final b = build();
    snap.restoreInto(b);
    for (var i = 0; i < 20; i++) {
      a.step(0.1);
      b.step(0.1);
      expect(gold(b), gold(a), reason: 'tick $i after the restore');
    }
    expect(gold(a), greaterThan(0));
  });
}
