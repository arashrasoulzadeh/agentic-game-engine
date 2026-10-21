import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridNavigator _nav() =>
    GridNavigator(cols: 12, rows: 12, terrainCost: (c, r) => 1);

typedef _Rig = ({World world, EntityId site});

/// A site at (8,3) needing builders, 4 s of work; builders are added by the tests.
_Rig _rig({double seconds = 4}) {
  final w = World(width: 12, height: 12);
  registerCoreComponents(w);
  final nav = _nav();
  w.addSystem(ConstructionSystem());
  w.addSystem(BuildSystem(nav));
  w.addSystem(RealtimeOrderSystem(fields: FlowFieldCache(nav)));
  w.storeOf<Treasury>().set(w.spawn(), Treasury('red', amounts: {'gold': 100}));
  final site = placeBuilding(
    w,
    nav,
    team: 'red',
    template: const {},
    col: 8,
    row: 3,
    cost: {'gold': 50},
    buildSeconds: seconds,
    needsBuilder: true,
  ).id!;
  return (world: w, site: site);
}

EntityId _builder(World w, {int col = 1, int row = 3, String team = 'red'}) {
  final e = w.spawn();
  w.components.applyToEntity(e, {
    'team': {'id': team},
    'gridPosition': {'col': col, 'row': row},
    'orderQueue': {'orders': []},
    'realtimeStats': {'speed': 8.0, 'attackInterval': 1.0},
    'builder': {},
  });
  return e;
}

void _run(World w, double seconds) {
  for (var i = 0; i < (seconds / 0.1).round(); i++) {
    w.step(0.1);
  }
}

void main() {
  test('without a builder the site does not progress', () {
    final r = _rig();
    _run(r.world, 5);
    expect(r.world.storeOf<Construction>().get(r.site)!.remaining, 4);
  });

  test(
    'an assigned builder walks to the site, builds it, and is freed when it is done',
    () {
      final r = _rig();
      final done = <EntityId>[];
      r.world.events.on<BuildingCompletedEvent>((e) => done.add(e.building));
      final b = _builder(r.world);
      expect(assignBuild(r.world, b, r.site), isTrue);

      _run(r.world, 12);

      expect(done, [r.site]);
      expect(r.world.storeOf<Construction>().has(r.site), isFalse);
      expect(
        r.world.storeOf<BuildWorker>().get(b)!.site,
        isNull,
        reason: 'freed',
      );
    },
  );

  test('progress only runs while the builder is next to the site', () {
    final r = _rig();
    final b = _builder(r.world, col: 0, row: 0);
    assignBuild(r.world, b, r.site);
    _run(
      r.world,
      0.5,
    ); // still walking (about 8 cells away at 8 cells/s needs a moment)
    final early = r.world.storeOf<Construction>().get(r.site)!.remaining;
    expect(early, 4, reason: 'no progress before arriving');
  });

  test('two builders finish in half the time', () {
    final solo = _rig(seconds: 6);
    assignBuild(solo.world, _builder(solo.world, col: 7, row: 3), solo.site);
    final duo = _rig(seconds: 6);
    assignBuild(duo.world, _builder(duo.world, col: 7, row: 3), duo.site);
    assignBuild(duo.world, _builder(duo.world, col: 7, row: 4), duo.site);

    _run(solo.world, 4);
    _run(duo.world, 4);

    expect(
      solo.world.storeOf<Construction>().has(solo.site),
      isTrue,
      reason: 'one builder: 6 s of work',
    );
    expect(
      duo.world.storeOf<Construction>().has(duo.site),
      isFalse,
      reason: 'two builders: ~3 s',
    );
  });

  test(
    'a builder of another team, an unassigned one, or one assigned elsewhere does not help',
    () {
      final r = _rig();
      r.world.storeOf<Treasury>().set(r.world.spawn(), Treasury('blue'));
      final enemy = _builder(r.world, col: 7, row: 3, team: 'blue');
      expect(
        assignBuild(r.world, enemy, r.site),
        isFalse,
        reason: 'different team',
      );
      _builder(r.world, col: 7, row: 3); // idle, adjacent, but never assigned

      _run(r.world, 3);
      expect(r.world.storeOf<Construction>().get(r.site)!.remaining, 4);
    },
  );

  test('assignBuild refuses non-builders and finished or missing sites', () {
    final r = _rig();
    final notBuilder = r.world.spawn();
    r.world.storeOf<Team>().set(notBuilder, Team('red'));
    expect(assignBuild(r.world, notBuilder, r.site), isFalse);
    final b = _builder(r.world);
    expect(assignBuild(r.world, b, 9999), isFalse);
    r.world.storeOf<Construction>().remove(r.site);
    expect(
      assignBuild(r.world, b, r.site),
      isFalse,
      reason: 'already finished',
    );
  });

  test('a building without needsBuilder still builds itself', () {
    final w = World(width: 12, height: 12);
    registerCoreComponents(w);
    w.addSystem(ConstructionSystem());
    w.storeOf<Treasury>().set(w.spawn(), Treasury('red'));
    final id = placeBuilding(
      w,
      _nav(),
      team: 'red',
      template: const {},
      col: 2,
      row: 2,
      buildSeconds: 1,
    ).id!;
    _run(w, 1.5);
    expect(w.storeOf<Construction>().has(id), isFalse);
  });

  test('the flag and the builder survive JSON', () {
    expect(
      Construction.fromJson(
        Construction(3, needsBuilder: true).toJson(),
      ).needsBuilder,
      isTrue,
    );
    expect(
      Construction.fromJson({'remaining': 2}).needsBuilder,
      isFalse,
      reason: 'old saves',
    );
    expect(BuildWorker.fromJson(BuildWorker(site: 7).toJson()).site, 7);
    expect(BuildWorker.fromJson({}).site, isNull);
  });
}
