import 'package:engine_core/engine_core.dart';

/// Walks [path] (a precomputed route from `findPath`) one waypoint at a
/// time — the platformer counterpart to `FollowBehavior`: horizontal
/// movement only (`Velocity.x`, via `_SetVelocityXAction`, same as
/// `FollowBehavior`), leaving `.y` to gravity/jump. A waypoint counts as
/// reached once within [arriveDistance] of it horizontally, advancing
/// to the next; once the last waypoint is reached, stops (`Velocity.x`
/// set to `0`) and stays stopped — this doesn't loop or replan.
///
/// Doesn't itself decide *when* to jump onto a higher waypoint — that
/// still comes from whatever normally triggers a jump for this entity
/// (a game-specific rule, e.g. "jump when the next waypoint is above
/// me"), since `findPath`'s 4-directional grid path doesn't distinguish
/// "step up" from "walk forward" the way an actual jump does.
class PathFollowBehavior implements Behavior {
  final List<PathPoint> path;
  final double speed;
  final double arriveDistance;
  int _index = 0;

  PathFollowBehavior(this.path, {this.speed = 80, this.arriveDistance = 8});

  /// The waypoint currently being walked toward, or `null` once the
  /// path is complete — useful for a game that wants to know (e.g. to
  /// decide whether to jump toward it).
  PathPoint? get currentTarget => _index < path.length ? path[_index] : null;

  @override
  Action decide(WorldView view, EntityId self) {
    final target = currentTarget;
    if (target == null) return _SetVelocityXAction(self, 0);

    final pos = view.component<Position>(self);
    if (pos == null) return _SetVelocityXAction(self, 0);

    final dx = target.x - pos.x;
    if (dx.abs() <= arriveDistance) {
      _index++;
      final next = currentTarget;
      if (next == null) return _SetVelocityXAction(self, 0);
      return _SetVelocityXAction(self, (next.x - pos.x).sign * speed);
    }
    return _SetVelocityXAction(self, dx.sign * speed);
  }
}

class _SetVelocityXAction implements Action {
  final EntityId entity;
  final double vx;

  _SetVelocityXAction(this.entity, this.vx);

  @override
  void apply(World world) {
    final store = world.storeOf<Velocity>();
    final existing = store.get(entity);
    store.set(entity, Velocity(vx, existing?.y ?? 0));
  }
}
