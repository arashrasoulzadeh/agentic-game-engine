import 'replay_recorder.dart';
import 'world.dart';

/// Records a play session as the world's seed plus one input snapshot per
/// step, so a bug seen once can be reproduced headlessly, byte for byte.
///
/// Determinism needs three things to line up: the same starting world, the same
/// seed (`World(seed:)`, which drives `world.random`), and the same inputs on
/// the same steps. This captures the last two; build the starting world the
/// same way both times (the same level, the same systems).
///
/// ```dart
/// final rec = SessionRecorder(world, captureInput: () => input.toJson());
/// while (playing) { rec.step(1 / 60); }
/// final saved = rec.toJson();                  // attach to the bug report
///
/// final fresh = buildWorld(seed: saved['seed'] as int);
/// SessionReplayer.run(fresh, saved, applyInput: (data) => input.restore(data));
/// ```
class SessionRecorder {
  SessionRecorder(this.world, {required this.captureInput});

  /// The world being recorded.
  final World world;

  /// Reads the inputs to record this step, as plain JSON.
  final Map<String, dynamic> Function() captureInput;

  final ReplayRecorder _inputs = ReplayRecorder();

  /// Steps the world by [dt], recording the inputs it ran with.
  void step(double dt) {
    _inputs.record(dt, captureInput());
    world.step(dt);
  }

  /// `{seed, frames}`: everything [SessionReplayer] needs besides the starting world.
  Map<String, dynamic> toJson() => {
    'seed': world.seed,
    'frames': _inputs.toJson(),
  };
}

/// Plays a [SessionRecorder] recording back into a freshly built world.
abstract final class SessionReplayer {
  /// Runs every recorded step against [world]: [applyInput] sets that step's
  /// inputs, then the world steps by the recorded `dt`. Returns the number of
  /// steps run.
  ///
  /// Throws [StateError] when [world] was built with a different seed than the
  /// recording, since the run could not match and would only look like a bug in
  /// the game.
  static int run(
    World world,
    Map<String, dynamic> recording, {
    required void Function(Map<String, dynamic> input) applyInput,
  }) {
    final seed = recording['seed'] as int;
    if (world.seed != seed) {
      throw StateError(
        'Recording was made with seed $seed but this world has seed '
        '${world.seed}; build the world with World(seed: $seed).',
      );
    }
    final frames = ReplayRecorder.fromJson(recording['frames'] as List).frames;
    for (final frame in frames) {
      applyInput(frame.data);
      world.step(frame.dt);
    }
    return frames.length;
  }
}
