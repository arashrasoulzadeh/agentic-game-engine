import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;

/// The stretch between fights where the hero walks to the next enemy.
///
/// The hero stays put on screen while the world slides past: the
/// [ParallaxScroller] layers, the last corpse and the incoming enemy all move
/// by the distance walked. That distance is one eased [Tween] (so the walk
/// starts and stops softly), plus a ping-pong [Tween] that bobs the hero's
/// steps; the walk ends when the distance tween completes. Needs `TweenSystem`
/// in the world.
class WalkPhase {
  WalkPhase({
    required this.scroller,
    this.speed = 70,
    this.distance = 190,
    this.bobHeight = 2,
  });

  final ParallaxScroller scroller;

  /// World units per second.
  final double speed;

  /// How far off the enemy starts from its anchor.
  final double distance;

  /// Peak vertical lift of a step, in world units.
  final double bobHeight;

  EntityId? _walk;
  EntityId? _bob;
  EntityId? _hero;
  EntityId? _enemy;
  EntityId? _corpse;
  double _done = 0;
  double _heroY = 0;
  double _enemyX = 0;
  double _enemyY = 0;

  bool get active => _walk != null;

  /// Starts walking [hero] towards [enemy], which stands [distance] to the
  /// right of its anchor and must arrive at [enemy]'s `Position.x - distance`
  /// (its current `x` is taken as the start). [corpse] slides off with the
  /// ground and is removed when the walk ends.
  void start(
    World world, {
    required EntityId hero,
    required EntityId enemy,
    EntityId? corpse,
  }) {
    final pos = world.storeOf<Position>();
    _hero = hero;
    _enemy = enemy;
    _corpse = corpse;
    _done = 0;
    _heroY = pos.get(hero)?.y ?? 0;
    _enemyX = (pos.get(enemy)?.x ?? 0) - distance;
    _enemyY = pos.get(enemy)?.y ?? 0;
    _walk = world.spawn();
    world.storeOf<Tween>().set(
      _walk!,
      Tween(
        from: 0,
        to: distance,
        duration: distance / speed,
        easing: EasingType.easeInOutQuad,
      ),
    );
    _bob = world.spawn();
    world.storeOf<Tween>().set(
      _bob!,
      Tween(from: 0, to: bobHeight, duration: 0.12, pingPong: true),
    );
  }

  /// Applies this tick's progress. Returns true on the tick the walk ends.
  bool update(World world) {
    final walk = _walk == null ? null : world.storeOf<Tween>().get(_walk!);
    final bob = _bob == null ? null : world.storeOf<Tween>().get(_bob!);
    final pos = world.storeOf<Position>();
    final h = _hero == null ? null : pos.get(_hero!);
    final e = _enemy == null ? null : pos.get(_enemy!);
    if (walk == null || bob == null || h == null || e == null) return false;

    final step = walk.value - _done;
    _done = walk.value;
    scroller.scroll(world, step);
    if (_corpse != null) pos.get(_corpse!)?.x -= step;
    e.x = _enemyX + distance - _done;
    h.y = _heroY - bob.value;

    if (!walk.isComplete) return false;
    h.y = _heroY;
    e.y = _enemyY;
    world.destroy(_walk!);
    world.destroy(_bob!);
    if (_corpse != null) world.destroy(_corpse!);
    _walk = _bob = _corpse = null;
    return true;
  }
}
