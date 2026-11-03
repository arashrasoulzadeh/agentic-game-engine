import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

void main() {
  test('hello world: a bouncing ball in a handful of lines', () {
    final game = GameBuilder.create(width: 100, height: 100, fixedStep: 1 / 60);
    final ball = game.spawn([Position(50, 50), Velocity(90, 70)]);
    game.world.addSystemFn('bounce', (w, dt) {
      final p = w.getComponent<Position>(ball)!;
      final v = w.getComponent<Velocity>(ball)!;
      if (p.x < 0 || p.x > w.width) v.x = -v.x;
      if (p.y < 0 || p.y > w.height) v.y = -v.y;
    });
    for (var frame = 0; frame < 600; frame++) {
      game.update(1 / 60);
    }
    final p = game.world.getComponent<Position>(ball)!;
    expect(p.x, inInclusiveRange(-5, 105));
    expect(p.y, inInclusiveRange(-5, 105));
  });

  test('create registers components and installs the core preset', () {
    final game = GameBuilder.create(width: 10, height: 10);
    expect(game.world.components.isRegistered('position'), isTrue);
    expect(game.world.systemOrder, contains('movement'));
    expect(game.world.validateSystemOrder(), isEmpty);
  });

  test('presets: false leaves the world without systems', () {
    final game = GameBuilder.create(width: 10, height: 10, presets: false);
    expect(game.world.systemOrder, isEmpty);
    expect(game.world.components.isRegistered('position'), isTrue);
  });

  test('seed reaches the world and extra registrars run', () {
    var registered = 0;
    final game = GameBuilder.create(
      width: 10,
      height: 10,
      seed: 99,
      register: [(w) => registered++],
    );
    expect(game.world.seed, 99);
    expect(registered, 1);
  });

  test('without a fixed step each update is one step of that length', () {
    final game = GameBuilder.create(width: 10, height: 10);
    final dts = <double>[];
    game.world.addSystemFn('probe', (_, dt) => dts.add(dt));
    expect(game.update(0.02), 1);
    expect(game.update(0.05), 1);
    expect(dts, [0.02, 0.05]);
  });

  test('with a fixed step, 1 second of frames is 60 steps at any rate', () {
    int steps(double frame, int frames) {
      final game = GameBuilder.create(width: 10, height: 10, fixedStep: 1 / 60);
      var total = 0;
      for (var i = 0; i < frames; i++) {
        total += game.update(frame);
      }
      return total;
    }

    expect(steps(1 / 30, 30), 60);
    expect(steps(1 / 144, 144), 60);
  });

  test('pause freezes simulated time and resume continues without a burst', () {
    final game = GameBuilder.create(width: 10, height: 10, fixedStep: 0.1);
    var fired = 0;
    game.world.after(0.3, () => fired++);
    game.update(0.2);
    game.pause();
    expect(game.isPaused, isTrue);
    expect(game.update(10), 0);
    expect(game.world.tick, 2);
    game.resume();
    expect(game.update(0.1), 1);
    expect(fired, 1);
    expect(game.update(0.1), 1);
  });

  test('stop ends the loop for good and is idempotent', () {
    final game = GameBuilder.create(width: 10, height: 10);
    game.stop();
    game.stop();
    expect(game.isStopped, isTrue);
    expect(game.update(0.1), 0);
    expect(game.world.tick, 0);
  });

  test('spawn shortcuts delegate to the world', () {
    final game = GameBuilder.create(width: 10, height: 10);
    final a = game.spawnAt(1, 2);
    final b = game.spawn([Position(3, 4)]);
    final c = game.entity().at(5, 6).build();
    expect(game.world.getComponent<Position>(a)!.y, 2);
    expect(game.world.getComponent<Position>(b)!.x, 3);
    expect(c.get<Position>()!.x, 5);
  });
}
