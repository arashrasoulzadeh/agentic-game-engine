import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridNavigator _nav() =>
    GridNavigator(cols: 12, rows: 12, terrainCost: (c, r) => 1);

const _knight = {
  'unitStats': {'maxHp': 20, 'hp': 20, 'attack': 5, 'defense': 2},
};

typedef _Rig = ({World world, EntityId stable, Treasury treasury});

/// A stable that makes knights, but only for a team that has `barracks`.
_Rig _rig({List<String> requires = const ['barracks']}) {
  final w = World(width: 12, height: 12);
  registerCoreComponents(w);
  w.addSystem(ConstructionSystem());
  w.addSystem(ProductionSystem(_nav()));
  final t = Treasury('red', amounts: {'gold': 100});
  w.storeOf<Treasury>().set(w.spawn(), t);
  final stable = w.spawn();
  w.storeOf<Team>().set(stable, Team('red'));
  w.storeOf<GridPosition>().set(stable, GridPosition(6, 6));
  w.storeOf<Producer>().set(
    stable,
    Producer(
      cost: {'gold': 30},
      seconds: 1,
      template: _knight,
      requires: requires,
    ),
  );
  return (world: w, stable: stable, treasury: t);
}

void _run(World w, double seconds) {
  for (var i = 0; i < (seconds / 0.1).round(); i++) {
    w.step(0.1);
  }
}

EntityId _barracks(World w, String team, {double buildSeconds = 0}) {
  final result = placeBuilding(
    w,
    _nav(),
    team: team,
    template: {
      'provides': {
        'tech': ['barracks'],
      },
    },
    col: 2,
    row: 2,
    buildSeconds: buildSeconds,
  );
  return result.id!;
}

void main() {
  test(
    'a producer with an unmet prerequisite does nothing and says what is missing, once',
    () {
      final r = _rig();
      final events = <ProductionLockedEvent>[];
      r.world.events.on<ProductionLockedEvent>(events.add);
      queueProduction(r.world, r.stable);

      _run(r.world, 5);

      expect(events.length, 1);
      expect(events.single.missing, {'barracks'});
      expect(
        r.treasury.of('gold'),
        100,
        reason: 'nothing charged while locked',
      );
      expect(r.world.storeOf<Producer>().get(r.stable)!.progress, 0);
    },
  );

  test('a finished building that Provides the tech unlocks it', () {
    final r = _rig();
    queueProduction(r.world, r.stable);
    _barracks(r.world, 'red');
    _run(r.world, 3);
    expect(
      r.world.storeOf<Producer>().get(r.stable)!.queued,
      0,
      reason: 'a knight was made',
    );
    expect(r.treasury.of('gold'), 70);
  });

  test(
    'a building still under construction does not count until it is finished',
    () {
      final r = _rig();
      queueProduction(r.world, r.stable);
      _barracks(r.world, 'red', buildSeconds: 3);
      _run(r.world, 2);
      expect(r.world.storeOf<Producer>().get(r.stable)!.progress, 0);
      _run(r.world, 3);
      expect(r.world.storeOf<Producer>().get(r.stable)!.queued, 0);
    },
  );

  test('another team\'s building does not unlock it', () {
    final r = _rig();
    queueProduction(r.world, r.stable);
    r.world.storeOf<Treasury>().set(
      r.world.spawn(),
      Treasury('blue'),
    ); // placeBuilding needs one
    _barracks(r.world, 'blue');
    _run(r.world, 2);
    expect(r.treasury.of('gold'), 100);
  });

  test('destroying the providing building locks the tech again', () {
    final r = _rig();
    final b = _barracks(r.world, 'red');
    expect(availableTech(r.world, 'red'), {'barracks'});
    r.world.destroy(b);
    expect(availableTech(r.world, 'red'), isEmpty);
  });

  test('grantTech unlocks by name, per team, without any building', () {
    final r = _rig(requires: ['feudalism']);
    queueProduction(r.world, r.stable);
    grantTech(r.world, 'blue', 'feudalism');
    _run(r.world, 1);
    expect(r.treasury.of('gold'), 100, reason: 'blue\'s tech is not red\'s');

    grantTech(r.world, 'red', 'feudalism');
    grantTech(
      r.world,
      'red',
      'feudalism',
    ); // idempotent, one TechState per team
    _run(r.world, 3);
    expect(r.treasury.of('gold'), 70);
    expect(r.world.storeOf<TechState>().length, 2);
  });

  test(
    'requires nothing means no gate, and several requirements are all needed',
    () {
      final open = _rig(requires: const []);
      queueProduction(open.world, open.stable);
      _run(open.world, 3);
      expect(open.treasury.of('gold'), 70);

      final both = _rig(requires: ['a', 'b']);
      grantTech(both.world, 'red', 'a');
      expect(missingTech(both.world, 'red', ['a', 'b']), {'b'});
      grantTech(both.world, 'red', 'b');
      expect(missingTech(both.world, 'red', ['a', 'b']), isEmpty);
    },
  );

  test('components and the prerequisite list survive JSON', () {
    expect(
      TechState.fromJson(
        TechState('red', researched: {'b', 'a'}).toJson(),
      ).researched,
      {'a', 'b'},
    );
    expect(Provides.fromJson(Provides({'x'}).toJson()).tech, {'x'});
    final p = Producer.fromJson(
      Producer(
        cost: {},
        seconds: 1,
        template: {},
        requires: ['barracks'],
      ).toJson(),
    );
    expect(p.requires, ['barracks']);
    expect(
      Producer.fromJson({'seconds': 1}).requires,
      isEmpty,
      reason: 'old saves have no field',
    );
  });
}
