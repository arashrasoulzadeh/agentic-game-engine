import 'dart:ui' show Offset;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;

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

  bool _animated = false;
  EntityId? _walk;
  EntityId? _bob;
  EntityId? _hero;
  EntityId? _enemy;
  List<EntityId> _corpses = [];
  List<EntityId> _companions = [];
  final Map<EntityId, Offset> _offsets = {};
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
    List<EntityId> corpses = const [],
    List<EntityId> companions = const [],
  }) {
    final pos = world.componentsOf<Position>();
    _hero = hero;
    _enemy = enemy;
    _corpses = [?corpse, ...corpses];
    // Companions (the rest of a squad) keep their place relative to [enemy]
    // while it walks in.
    _companions = companions;
    _offsets.clear();
    final ex = pos.get(enemy)?.x ?? 0;
    final ey = pos.get(enemy)?.y ?? 0;
    for (final c in companions) {
      final p = pos.get(c);
      if (p != null) _offsets[c] = Offset(p.x - ex, p.y - ey);
    }
    _done = 0;
    // A hero with a `walk` clip plays it for the whole walk; without one the
    // bob below is the only step cue.
    _animated =
        world
            .componentsOf<SpriteStates>()
            .get(hero)
            ?.clips
            .containsKey('walk') ??
        false;
    if (_animated) playSpriteState(world, hero, 'walk');
    _heroY = pos.get(hero)?.y ?? 0;
    _enemyX = (pos.get(enemy)?.x ?? 0) - distance;
    _enemyY = pos.get(enemy)?.y ?? 0;
    _walk = world.spawn();
    world.componentsOf<Tween>().set(
      _walk!,
      Tween(
        from: 0,
        to: distance,
        duration: distance / speed,
        easing: EasingType.easeInOutQuad,
      ),
    );
    _bob = world.spawn();
    world.componentsOf<Tween>().set(
      _bob!,
      Tween(from: 0, to: bobHeight, duration: 0.12, pingPong: true),
    );
  }

  /// Applies this tick's progress. Returns true on the tick the walk ends.
  bool update(World world) {
    final walk = _walk == null ? null : world.componentsOf<Tween>().get(_walk!);
    final bob = _bob == null ? null : world.componentsOf<Tween>().get(_bob!);
    final pos = world.componentsOf<Position>();
    final h = _hero == null ? null : pos.get(_hero!);
    final e = _enemy == null ? null : pos.get(_enemy!);
    if (walk == null || bob == null || h == null || e == null) return false;

    final step = walk.value - _done;
    _done = walk.value;
    scroller.scroll(world, step);
    for (final c in _corpses) {
      pos.get(c)?.x -= step;
    }
    e.x = _enemyX + distance - _done;
    for (final c in _companions) {
      final off = _offsets[c];
      final p = pos.get(c);
      if (off != null && p != null) {
        p.x = e.x + off.dx;
        p.y = _enemyY + off.dy;
      }
    }
    h.y = _heroY - bob.value;

    if (!walk.isComplete) return false;
    h.y = _heroY;
    e.y = _enemyY;
    if (_animated) {
      final rest = world.componentsOf<SpriteStates>().get(_hero!)?.restState;
      playSpriteState(world, _hero!, rest ?? 'idle');
      _animated = false;
    }
    world.destroy(_walk!);
    world.destroy(_bob!);
    for (final c in _corpses) {
      world.destroy(c);
    }
    _corpses = [];
    _companions = [];
    _walk = _bob = null;
    return true;
  }
}
