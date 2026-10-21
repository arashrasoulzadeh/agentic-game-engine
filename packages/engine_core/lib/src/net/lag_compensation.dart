import '../ecs/entity.dart';
import '../ecs/ring_buffer.dart';
import '../ecs/world.dart';
import '../physics/position.dart';
import 'world_snapshot.dart';

/// A short history of where every entity was, per tick -- what a server needs to
/// answer "where was the target when the shooter *saw* it?".
///
/// A shooter fires at what they see on their screen, which is the world as it was
/// roughly `latency + interpolation delay` ago. Checking the shot against the
/// server's *current* positions makes players miss targets that were clearly
/// under the crosshair; [positionAt] rewinds to the shooter's view of the world
/// so the hit test is fair to them.
///
/// Positions between recorded ticks are interpolated, so a fractional tick (from
/// a latency that is not a whole number of ticks) is fine.
class PositionHistory {
  PositionHistory({int capacity = 64}) : _frames = RingBuffer<_Frame>(capacity);

  final RingBuffer<_Frame> _frames;

  /// Records every entity's `Position` at `world.tick`.
  void record(World world) {
    final store = world.storeOf<Position>();
    _add(world.tick, {
      for (var i = 0; i < store.length; i++)
        store.entityAt(i): _P(store.denseAt(i).x, store.denseAt(i).y),
    });
  }

  /// Records positions from a snapshot (e.g. one received from a server), so a
  /// client can interpolate remote entities between updates.
  void recordSnapshot(WorldSnapshot snapshot) {
    _add(snapshot.tick, {
      for (final e in snapshot.entities.entries)
        if (e.value['position'] case final Map p)
          e.key: _P((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
    });
  }

  void _add(int tick, Map<EntityId, _P> positions) {
    final last = _frames.last;
    if (last != null && last.tick == tick) {
      // Same tick recorded twice (e.g. after a rollback): the later one wins.
      final all = _frames.toList()..removeLast();
      _frames.clear();
      all.forEach(_frames.add);
    }
    _frames.add(_Frame(tick, positions));
  }

  /// The oldest and newest recorded ticks, or null when empty.
  (int, int)? get range {
    final all = _frames.toList();
    return all.isEmpty ? null : (all.first.tick, all.last.tick);
  }

  /// Where [entity] was at [tick] (fractions interpolate; outside the recorded
  /// range it clamps to the nearest recorded tick). Null if never recorded.
  Position? positionAt(EntityId entity, double tick) {
    final frames = _frames
        .toList()
        .where((f) => f.positions.containsKey(entity))
        .toList();
    if (frames.isEmpty) return null;
    if (tick <= frames.first.tick)
      return frames.first.positions[entity]!.toPosition();
    if (tick >= frames.last.tick)
      return frames.last.positions[entity]!.toPosition();
    for (var i = 1; i < frames.length; i++) {
      if (tick <= frames[i].tick) {
        final a = frames[i - 1], b = frames[i];
        final t = (tick - a.tick) / (b.tick - a.tick);
        final pa = a.positions[entity]!, pb = b.positions[entity]!;
        return Position(pa.x + (pb.x - pa.x) * t, pa.y + (pb.y - pa.y) * t);
      }
    }
    return frames.last.positions[entity]!.toPosition();
  }

  /// Every entity's position at [tick].
  Map<EntityId, Position> rewind(double tick) {
    final ids = <EntityId>{
      for (final f in _frames.toList()) ...f.positions.keys,
    };
    return {
      for (final id in ids)
        if (positionAt(id, tick) case final p?) id: p,
    };
  }

  /// The tick to rewind to for a shooter whose view lags the server by
  /// [latencyTicks] one-way (round trip / 2) plus [interpolationTicks] of render
  /// delay. Pass `world.tick` for [currentTick].
  static double rewindTick({
    required double currentTick,
    required double latencyTicks,
    double interpolationTicks = 0,
  }) => currentTick - latencyTicks - interpolationTicks;

  /// Converts a duration to (fractional) ticks at [fixedDt] seconds per tick.
  static double ticksFor(Duration d, double fixedDt) =>
      d.inMicroseconds / 1e6 / fixedDt;

  void clear() => _frames.clear();
}

class _P {
  const _P(this.x, this.y);
  final double x, y;
  Position toPosition() => Position(x, y);
}

class _Frame {
  _Frame(this.tick, this.positions);
  final int tick;
  final Map<EntityId, _P> positions;
}
