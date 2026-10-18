import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridNavigator _nav() => GridNavigator(cols: 12, rows: 12, terrainCost: (c, r) => 1);

const _worker = {
  'realtimeStats': {'speed': 6.0, 'attackInterval': 1.0},
  'orderQueue': {'orders': []},
  'gatherer': {'capacity': 4, 'secondsPerUnit': 0.5},
};

typedef _Rig = ({World world, EntityId worker, EntityId mine, EntityId hall, Treasury treasury});

/// A worker at (1,1), a gold mine at (6,1), a town hall at (1,5).
_Rig _rig({int gold = 6, bool withDepot = true}) {
  final w = World(width: 12, height: 12);
  registerCoreComponents(w);
  final nav = _nav();
  final fields = FlowFieldCache(nav);
  w.addSystem(GatherSystem(nav));
  w.addSystem(RealtimeOrderSystem(fields: fields));
  final treasury = Treasury('red');
  w.storeOf<Treasury>().set(w.spawn(), treasury);
  final worker = w.spawn();
  w.components.applyToEntity(worker, {
    ..._worker,
    'team': {'id': 'red'},
    'gridPosition': {'col': 1, 'row': 1},
  });
  final mine = w.spawn();
  w.components.applyToEntity(mine, {
    'resourceNode': {'resource': 'gold', 'amount': gold},
    'gridPosition': {'col': 6, 'row': 1},
  });
  final hall = w.spawn();
  if (withDepot) {
    w.components.applyToEntity(hall, {
      'depot': {},
      'team': {'id': 'red'},
      'gridPosition': {'col': 1, 'row': 5},
    });
  }
  return (world: w, worker: worker, mine: mine, hall: hall, treasury: treasury);
}

void _run(World w, double seconds, {double dt = 0.1}) {
  for (var i = 0; i < (seconds / dt).round(); i++) {
    w.step(dt);
  }
}

void main() {
  group('gathering', () {
    test('walks to the node, harvests, hauls to the depot and delivers into the treasury', () {
      final r = _rig();
      final delivered = <ResourceDeliveredEvent>[];
      r.world.events.on<ResourceDeliveredEvent>(delivered.add);
      expect(assignGather(r.world, r.worker, r.mine), isTrue);

      _run(r.world, 40);

      expect(r.treasury.of('gold'), 6, reason: 'the whole mine ends up in the treasury');
      expect(delivered.map((e) => e.amount), [4, 2], reason: 'capacity 4, then the last 2');
      expect(r.world.entities.isAlive(r.mine), isFalse, reason: 'an empty node is removed');
      expect(r.world.storeOf<Gatherer>().get(r.worker)!.phase, GatherPhase.idle);
    });

    test('harvesting takes secondsPerUnit per unit', () {
      final r = _rig();
      r.world.storeOf<GridPosition>().get(r.worker)!
        ..col = 5
        ..row = 1; // already next to the mine
      assignGather(r.world, r.worker, r.mine);
      _run(r.world, 1.2); // one tick to start, then 0.5 s per unit
      final g = r.world.storeOf<Gatherer>().get(r.worker)!;
      expect(g.carried, 2);
      expect(r.world.storeOf<ResourceNode>().get(r.mine)!.amount, 4);
    });

    test('without a depot the haul waits, kept, until one exists', () {
      final r = _rig(withDepot: false);
      assignGather(r.world, r.worker, r.mine);
      _run(r.world, 30);
      final g = r.world.storeOf<Gatherer>().get(r.worker)!;
      expect((g.phase, g.carried), (GatherPhase.toDepot, 4));
      expect(r.treasury.of('gold'), 0);
    });

    test('an unfinished depot does not accept deliveries', () {
      final r = _rig();
      r.world.storeOf<Construction>().set(r.hall, Construction(1000));
      assignGather(r.world, r.worker, r.mine);
      _run(r.world, 30);
      expect(r.treasury.of('gold'), 0);
    });

    test('assignGather refuses non-gatherers and empty or missing nodes', () {
      final r = _rig(gold: 0);
      expect(assignGather(r.world, r.worker, r.mine), isFalse, reason: 'empty node');
      expect(assignGather(r.world, r.hall, r.mine), isFalse, reason: 'not a gatherer');
      expect(assignGather(r.world, r.worker, 9999), isFalse);
    });

    test('switching resource drops what was carried', () {
      final r = _rig();
      final g = r.world.storeOf<Gatherer>().get(r.worker)!
        ..carrying = 'wood'
        ..carried = 3;
      assignGather(r.world, r.worker, r.mine);
      expect((g.carrying, g.carried), (null, 0));
    });

    test('is deterministic, and a world restored mid-haul finishes identically', () {
      final a = _rig();
      assignGather(a.world, a.worker, a.mine);
      _run(a.world, 6);
      final snap = WorldSnapshot.capture(a.world);
      _run(a.world, 30);

      final b = _rig();
      snap.restoreInto(b.world);
      _run(b.world, 30);

      // Compared as data: map key order differs after a restore, the content must not.
      expect(WorldSnapshot.capture(b.world).toJson(), WorldSnapshot.capture(a.world).toJson());
      expect(a.treasury.of('gold'), 6);
    });

    test('with several depots the nearest one is used', () {
      final r = _rig();
      final near = r.world.spawn();
      r.world.components.applyToEntity(near, {
        'depot': {},
        'team': {'id': 'red'},
        'gridPosition': {'col': 6, 'row': 3},
      });
      final events = <ResourceDeliveredEvent>[];
      r.world.events.on<ResourceDeliveredEvent>(events.add);
      assignGather(r.world, r.worker, r.mine);
      _run(r.world, 15);
      final p = r.world.storeOf<GridPosition>().get(r.worker)!;
      expect(p.chebyshev(GridPosition(6, 3)), lessThanOrEqualTo(3), reason: 'it stayed near the mine');
      expect(events, isNotEmpty);
    });
  });

  group('construction', () {
    ({World world, Treasury treasury}) rig({int gold = 100}) {
      final w = World(width: 12, height: 12);
      registerCoreComponents(w);
      w.addSystem(ConstructionSystem());
      w.addSystem(ProductionSystem(_nav()));
      final t = Treasury('red', amounts: {'gold': gold});
      w.storeOf<Treasury>().set(w.spawn(), t);
      return (world: w, treasury: t);
    }

    const barracks = {
      'producer': {
        'cost': {'gold': 10},
        'seconds': 1.0,
        'template': {
          'unitStats': {'maxHp': 5, 'hp': 5, 'attack': 1, 'defense': 0},
        },
      },
    };

    test('placing takes the cost and spawns the building under construction', () {
      final r = rig();
      final res = placeBuilding(r.world, _nav(),
          team: 'red', template: barracks, col: 3, row: 3, cost: {'gold': 40}, buildSeconds: 5);
      expect(res.failure, isNull);
      expect(r.treasury.of('gold'), 60);
      final id = res.id!;
      expect(r.world.storeOf<Construction>().get(id)!.remaining, 5);
      expect(r.world.storeOf<Team>().get(id)!.id, 'red');
      expect(r.world.storeOf<GridPosition>().get(id)!.col, 3);
    });

    test('it completes after buildSeconds and announces it once', () {
      final r = rig();
      final done = <EntityId>[];
      r.world.events.on<BuildingCompletedEvent>((e) => done.add(e.building));
      final id =
          placeBuilding(r.world, _nav(), team: 'red', template: barracks, col: 3, row: 3, buildSeconds: 2).id!;
      _run(r.world, 1.5);
      expect(r.world.storeOf<Construction>().has(id), isTrue);
      _run(r.world, 1.0);
      expect(r.world.storeOf<Construction>().has(id), isFalse);
      expect(done, [id]);
    });

    test('a producer under construction makes nothing until it is finished', () {
      final r = rig();
      final id =
          placeBuilding(r.world, _nav(), team: 'red', template: barracks, col: 3, row: 3, buildSeconds: 3).id!;
      queueProduction(r.world, id);
      _run(r.world, 2.5);
      expect(r.world.storeOf<Producer>().get(id)!.progress, 0);
      expect(r.treasury.of('gold'), 100, reason: 'nothing was charged for a unit yet');
      _run(r.world, 3);
      expect(r.world.storeOf<Producer>().get(id)!.queued, 0, reason: 'one unit built after completion');
    });

    test('zero buildSeconds is finished at once', () {
      final r = rig();
      final id = placeBuilding(r.world, _nav(), team: 'red', template: barracks, col: 3, row: 3).id!;
      expect(r.world.storeOf<Construction>().has(id), isFalse);
    });

    test('every refusal reason, and a refusal spends nothing', () {
      final r = rig(gold: 10);
      final nav = _nav();
      BuildFailure? fail(int c, int rr, {String team = 'red', int cost = 0}) => placeBuilding(r.world, nav,
              team: team, template: barracks, col: c, row: rr, cost: {'gold': cost})
          .failure;

      expect(fail(-1, 0), BuildFailure.outOfBounds);
      expect(fail(99, 0), BuildFailure.outOfBounds);
      expect(fail(2, 2, team: 'blue'), BuildFailure.noTreasury);
      expect(fail(2, 2, cost: 50), BuildFailure.cantAfford);
      expect(r.treasury.of('gold'), 10);

      expect(fail(2, 2), isNull);
      expect(fail(2, 2), BuildFailure.occupied);

      final walled = GridNavigator(cols: 12, rows: 12, terrainCost: (c, rr) => c == 7 ? null : 1);
      expect(
        placeBuilding(r.world, walled, team: 'red', template: barracks, col: 7, row: 1).failure,
        BuildFailure.blocked,
      );
      expect(r.world.entities.all.length, 2, reason: 'only the treasury and the one building exist');
    });
  });
}
