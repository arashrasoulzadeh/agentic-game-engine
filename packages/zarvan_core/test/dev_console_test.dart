import 'package:test/test.dart';
import 'package:zarvan_core/zarvan_core.dart';

(DevConsole, World) _make() {
  final world = World(width: 200, height: 100);
  registerCoreComponents(world);
  final prefabs = PrefabRegistry()
    ..register(
      Prefab(
        name: 'coin',
        entities: [
          LevelEntity(
            name: 'coin',
            components: {
              'position': {'x': 0, 'y': 0},
            },
          ),
        ],
      ),
    );
  return (DevConsole(worldOf: () => world, prefabs: prefabs), world);
}

EntityId _thing(World world, double x, double y) {
  final id = world.spawn();
  world.componentsOf<Position>().set(id, Position(x, y));
  return id;
}

void main() {
  test('help lists commands and describes one', () {
    final (c, _) = _make();
    expect(c.run('help'), allOf(contains('timescale'), contains('spawn')));
    expect(c.run('help teleport'), contains('<id> <x> <y>'));
    expect(c.run('help teleprt'), contains('did you mean "teleport"'));
  });

  test(
    'unknown commands and mistakes give readable errors, not exceptions',
    () {
      final (c, _) = _make();
      expect(c.run('timescael 2'), contains('did you mean "timescale"'));
      expect(
        c.run('timescale fast'),
        startsWith('error: timescale must be a number'),
      );
      expect(c.run('kill 999'), 'error: entity 999 does not exist');
      expect(c.run('teleport 1'), startsWith('error: usage: teleport'));
    },
  );

  test('time commands drive World.timeScale, step and hit-stop', () {
    final (c, w) = _make();
    expect(c.run('timescale 0.25'), 'timeScale 0.25');
    expect(w.timeScale, 0.25);
    c.run('pause');
    expect(w.timeScale, 0);
    c.run('resume');
    expect(w.timeScale, 1);
    final before = w.tick;
    expect(c.run('step 5'), startsWith('stepped 5'));
    expect(w.tick, before + 5);
    c.run('hitstop 0.5');
    expect(w.isHitStopped, isTrue);
    expect(c.run('tick'), contains('hit-stop'));
    expect(c.run('timescale -1'), contains('0 or more'));
  });

  test('spawn places a prefab; unknown prefab suggests and lists', () {
    final (c, w) = _make();
    final out = c.run('spawn coin 40 30');
    expect(out, startsWith('spawned coin as'));
    final id = int.parse(out.split(' ').last);
    final p = w.componentsOf<Position>().get(id)!;
    expect((p.x, p.y), (40, 30));
    expect(
      c.run('spawn cion'),
      allOf(contains('did you mean "coin"'), contains('known: coin')),
    );
    expect(
      c.run('spawn coin'),
      startsWith('spawned'),
    ); // defaults to the middle
  });

  test('entities, inspect, teleport, set and kill edit and read the world', () {
    final (c, w) = _make();
    final id = _thing(w, 1, 2);
    expect(c.run('entities'), contains('position: 1'));
    expect(c.run('entities position'), '$id');
    expect(c.run('inspect $id'), contains('"x": 1'));
    c.run('teleport $id 10 20');
    expect(
      (
        w.componentsOf<Position>().get(id)!.x,
        w.componentsOf<Position>().get(id)!.y,
      ),
      (10, 20),
    );
    expect(c.run('set $id position x 99'), '$id.position.x = 99');
    expect(w.componentsOf<Position>().get(id)!.x, 99);
    expect(c.run('set $id position z 1'), contains('has no field "z"'));
    expect(c.run('set $id positon x 1'), contains('did you mean "position"'));
    c.run('kill $id');
    expect(w.entities.isAlive(id), isFalse);
  });

  test('systems prints the run order', () {
    final (c, w) = _make();
    w.addSystem(JointSystem());
    w.addSystem(MovementSystem());
    expect(c.run('systems'), 'joint -> movement');
    w.setSystemEnabled('movement', false);
    expect(c.run('systems'), 'joint -> movement (off)');
  });

  test('games add their own cheats', () {
    final (c, _) = _make();
    var gold = 0;
    c.addCommand(
      ConsoleCommand('give', 'Give gold', (a) {
        gold += int.parse(a.first);
        return 'gold $gold';
      }, usage: '<amount>'),
    );
    expect(c.run('give 50'), 'gold 50');
    expect(c.run('help give'), contains('<amount>'));
  });

  test('quoted arguments stay together', () {
    final (c, _) = _make();
    expect(c.run('echo "hello  big world" again'), 'hello  big world again');
  });

  group('history and completion', () {
    test('history collapses repeats and arrows walk it', () {
      final (c, _) = _make();
      c.run('tick');
      c.run('tick');
      c.run('echo a');
      expect(c.history, ['tick', 'echo a']);
      expect(c.previous(), 'echo a');
      expect(c.previous(), 'tick');
      expect(c.previous(), 'tick'); // stays at the oldest
      expect(c.next(), 'echo a');
      expect(c.next(), '');
      expect(c.next(), '');
    });

    test('completes command names, prefab names and component names', () {
      final (c, _) = _make();
      expect(c.complete('ti'), ['tick', 'timescale']);
      expect(c.complete(''), contains('help'));
      expect(c.complete('spawn '), ['coin']);
      expect(c.complete('spawn co'), ['coin']);
      expect(c.complete('set 1 pos'), contains('position'));
      expect(c.complete('help sp'), ['spawn']);
      expect(c.complete('tick '), isEmpty);
    });
  });

  test('the log keeps typed lines and output; clear empties it', () {
    final (c, _) = _make();
    c.run('echo hi');
    expect(c.log, ['> echo hi', 'hi']);
    c.run('clear');
    expect(c.log, isEmpty);
  });

  test('with no world running, commands say so', () {
    final c = DevConsole(worldOf: () => null);
    expect(c.run('tick'), 'error: no world is running');
    expect(c.run('help'), contains('tick')); // help needs no world
  });
}
