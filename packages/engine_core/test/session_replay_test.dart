import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:engine_core/engine_core_testing.dart';
import 'package:test/test.dart';

class _Input {
  bool right = false;
}

/// Moves right while the input is held, plus a random nudge each step, so the
/// final position depends on both the inputs and the seeded randomness.
class _Walker implements System {
  _Walker(this.input, this.id);
  final _Input input;
  final EntityId Function() id;
  @override
  String get name => 'walker';
  @override
  void update(World world, double dt) {
    final p = world.getComponent<Position>(id())!;
    if (input.right) p.x += 10 * dt;
    p.y += world.random.nextDouble();
  }
}

(World, _Input, EntityId Function()) _build(int seed) {
  final world = World(width: 100, height: 100, seed: seed);
  registerCoreComponents(world);
  final input = _Input();
  final hero = world.spawnWith([Position(0, 0)]);
  world.addSystem(_Walker(input, () => hero));
  return (world, input, () => hero);
}

void main() {
  test('a replay reproduces the recorded run exactly', () {
    final (world, input, _) = _build(7);
    final rec = SessionRecorder(
      world,
      captureInput: () => {'right': input.right},
    );
    for (var i = 0; i < 120; i++) {
      input.right = (i ~/ 30).isEven;
      rec.step(1 / 60);
    }
    final saved = jsonDecode(jsonEncode(rec.toJson())) as Map<String, dynamic>;
    final expected = canonicalJson(world.save());

    final (fresh, freshInput, _) = _build(saved['seed'] as int);
    final steps = SessionReplayer.run(
      fresh,
      saved,
      applyInput: (data) => freshInput.right = data['right'] as bool,
    );
    expect(steps, 120);
    expect(canonicalJson(fresh.save()), expected);
  });

  test('different inputs give a different result (the test can fail)', () {
    final (world, input, _) = _build(7);
    final rec = SessionRecorder(
      world,
      captureInput: () => {'right': input.right},
    );
    input.right = true;
    for (var i = 0; i < 30; i++) {
      rec.step(1 / 60);
    }
    final (fresh, freshInput, _) = _build(7);
    SessionReplayer.run(
      fresh,
      rec.toJson(),
      applyInput: (_) => freshInput.right = false,
    );
    expect(canonicalJson(fresh.save()), isNot(canonicalJson(world.save())));
  });

  test('a world with another seed is refused, naming both seeds', () {
    final (world, input, _) = _build(1);
    final rec = SessionRecorder(world, captureInput: () => {});
    rec.step(0.016);
    final (other, _, _) = _build(2);
    expect(
      () => SessionReplayer.run(other, rec.toJson(), applyInput: (_) {}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('seed 1'), contains('seed 2')),
        ),
      ),
    );
  });
}
