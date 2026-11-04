import 'package:test/test.dart';
import 'package:zarvan_core/zarvan_core.dart';

World _world() {
  final world = World(width: 1000, height: 1000);
  registerCoreComponents(world);
  return world;
}

EntityId _body(World w, double x, double y) {
  final id = w.spawn();
  w.componentsOf<Position>().set(id, Position(x, y));
  w.componentsOf<Velocity>().set(id, Velocity(0, 0));
  return id;
}

Position _pos(World w, EntityId id) => w.componentsOf<Position>().get(id)!;

void main() {
  group('ConveyorZone', () {
    test('drags bodies inside, not outside, and not itself', () {
      final w = _world()..addSystem(ConveyorZoneSystem());
      final belt = w.spawn();
      w.componentsOf<Position>().set(belt, Position(100, 100));
      w.componentsOf<Velocity>().set(belt, Velocity(0, 0));
      w.componentsOf<ConveyorZone>().set(
        belt,
        ConveyorZone(width: 64, height: 16, speedX: 60, speedY: -30),
      );
      final inside = _body(w, 110, 100);
      final outside = _body(w, 300, 100);
      w.step(0.5);
      expect(_pos(w, inside).x, closeTo(140, 1e-9));
      expect(_pos(w, inside).y, closeTo(85, 1e-9));
      expect(_pos(w, outside).x, 300);
      expect(_pos(w, belt).x, 100);
    });

    test('round-trips through JSON with defaults', () {
      final z = ConveyorZone.fromJson({'speedX': -5});
      expect((z.speedX, z.width, z.height), (-5, 64, 16));
      expect(ConveyorZone.fromJson(z.toJson()).speedX, -5);
    });
  });

  group('Teleporter', () {
    test('moves a body, emits an event, and cools down', () {
      final w = _world()..addSystem(TeleporterSystem());
      final pad = w.spawn();
      w.componentsOf<Position>().set(pad, Position(50, 50));
      w.componentsOf<Teleporter>().set(
        pad,
        Teleporter(targetX: 500, targetY: 400, cooldown: 1),
      );
      final seen = <Teleported>[];
      w.events.on<Teleported>(seen.add);
      final b = _body(w, 52, 50);
      w.step(0.1);
      expect((_pos(w, b).x, _pos(w, b).y), (500, 400));
      expect(seen.single.entity, b);
      _pos(w, b)
        ..x = 52
        ..y = 50;
      w.step(0.1);
      expect(_pos(w, b).x, 52, reason: 'still cooling down');
      for (var i = 0; i < 12; i++) {
        w.step(0.1);
      }
      expect(_pos(w, b).x, 500, reason: 'cooldown elapsed, teleports again');
    });

    test('can target another entity and ignores a missing one', () {
      final w = _world()..addSystem(TeleporterSystem());
      final dest = w.spawn();
      w.componentsOf<Position>().set(dest, Position(700, 10));
      final pad = w.spawn();
      w.componentsOf<Position>().set(pad, Position(0, 0));
      w.componentsOf<Teleporter>().set(pad, Teleporter(targetEntity: dest));
      final b = _body(w, 1, 1);
      w.step(0.1);
      expect((_pos(w, b).x, _pos(w, b).y), (700, 10));
      w.destroy(dest);
      _pos(w, b)
        ..x = 1
        ..y = 1;
      for (var i = 0; i < 10; i++) {
        w.step(0.1);
      }
      expect(_pos(w, b).x, 1);
    });

    test('are registered so worlds and the studio know them', () {
      final w = _world();
      expect(w.components.isRegistered('teleporter'), isTrue);
      expect(w.components.isRegistered('conveyorZone'), isTrue);
      final t = Teleporter.fromJson(Teleporter(targetX: 9).toJson());
      expect(t.targetX, 9);
      expect(t.cooldown, 0.5);
    });
  });

  group('DestructibleTiles', () {
    TileMap map() => TileMap(
      cols: 4,
      rows: 1,
      tileWidth: 10,
      tileHeight: 10,
      tiles: [1, 2, 2, 0],
      solidTileIds: {1, 2},
    );

    test('takes the configured number of hits then becomes air or rubble', () {
      final m = map();
      final d = DestructibleTiles(m, {
        2: const DestructibleTile(hits: 2, becomes: 0),
      });
      expect(d.hit(1, 0), isFalse);
      expect(m.tileAt(1, 0), 2);
      expect(d.hit(1, 0), isTrue);
      expect(m.tileAt(1, 0), 0);
      expect(m.isSolid(1, 0), isFalse);
    });

    test('unbreakable and out-of-range cells are untouched', () {
      final m = map();
      final d = DestructibleTiles(m, {2: const DestructibleTile()});
      expect(d.hit(0, 0), isFalse);
      expect(d.hit(9, 9), isFalse);
      expect(m.tileAt(0, 0), 1);
    });

    test('power and blast radius', () {
      final m = map();
      final d = DestructibleTiles(m, {
        2: const DestructibleTile(hits: 3, becomes: 3),
      });
      expect(d.hit(1, 0, power: 3), isTrue);
      expect(m.tileAt(1, 0), 3);
      expect(d.blast(25, 5, 4, power: 3), 1);
      expect(m.tileAt(2, 0), 3);
      expect(m.tileAt(0, 0), 1);
    });
  });
}
