/// One recorded frame: an arbitrary JSON-serializable snapshot (e.g. an
/// input state, an agent action) plus how long after the *previous*
/// frame it was captured.
class ReplayFrame {
  final double dt;
  final Map<String, dynamic> data;

  ReplayFrame(this.dt, this.data);

  Map<String, dynamic> toJson() => {'dt': dt, 'data': data};

  factory ReplayFrame.fromJson(Map<String, dynamic> json) => ReplayFrame(
        (json['dt'] as num).toDouble(),
        Map<String, dynamic>.from(json['data'] as Map),
      );
}

/// Captures a timestamped sequence of arbitrary JSON snapshots for
/// deterministic playback -- deliberately generic (not tied to
/// `InputState`, which lives in `engine_flutter` and would create a
/// backward dependency) so it works for input capture, recorded agent
/// actions, or any other per-tick data a game wants to replay.
///
/// Pair with [DeterministicRandom] (reset to the same seed before
/// replay) when the recorded game logic also consumes randomness --
/// the recording alone only reproduces *external* inputs, not internal
/// random choices.
class ReplayRecorder {
  final List<ReplayFrame> _frames = [];

  ReplayRecorder();

  /// Read-only view of everything recorded so far.
  List<ReplayFrame> get frames => List.unmodifiable(_frames);

  /// Records [data] as having occurred [dt] seconds after the last
  /// recorded frame (or after recording started, for the first frame).
  void record(double dt, Map<String, dynamic> data) {
    _frames.add(ReplayFrame(dt, data));
  }

  void clear() => _frames.clear();

  List<Map<String, dynamic>> toJson() => _frames.map((f) => f.toJson()).toList();

  factory ReplayRecorder.fromJson(List<dynamic> json) {
    final recorder = ReplayRecorder();
    for (final entry in json) {
      recorder._frames.add(ReplayFrame.fromJson(entry as Map<String, dynamic>));
    }
    return recorder;
  }
}

/// Plays back frames captured by a [ReplayRecorder], firing [onFrame]
/// for each one at the moment its recorded `dt` has elapsed -- mirrors
/// how the frames were originally captured tick-by-tick, rather than
/// replaying them all at once regardless of timing.
class ReplayPlayer {
  final List<ReplayFrame> _frames;
  int _index = 0;
  double _elapsedSinceLastFrame = 0;

  ReplayPlayer(List<ReplayFrame> frames) : _frames = List.of(frames);

  /// `true` once every recorded frame has been delivered.
  bool get isFinished => _index >= _frames.length;

  /// Advances playback by [dt] seconds, invoking [onFrame] once for
  /// each recorded frame whose cumulative `dt` falls within this step
  /// -- a single large `dt` (e.g. a stalled frame) can deliver more
  /// than one recorded frame in one call, matching what a live run
  /// experiencing the same stall would have produced.
  void step(double dt, void Function(Map<String, dynamic> data) onFrame) {
    _elapsedSinceLastFrame += dt;
    while (!isFinished && _elapsedSinceLastFrame >= _frames[_index].dt) {
      _elapsedSinceLastFrame -= _frames[_index].dt;
      onFrame(_frames[_index].data);
      _index++;
    }
  }

  /// Rewinds to the start of the recording, so the same frames replay
  /// again from the beginning.
  void reset() {
    _index = 0;
    _elapsedSinceLastFrame = 0;
  }
}
