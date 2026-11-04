import 'dart:math' as math;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_platformer/zarvan_platformer.dart';

import 'combat_components.dart';
import 'enemy_powers.dart';

class _Lunge {
  _Lunge(this.home, this.target, this.delay, this.outSeconds);
  final double home;
  final double target;

  /// Wait before the run starts, so a short run still ends as the blow lands.
  final double delay;
  final double outSeconds;
  double t = 0;
}

/// Makes a melee attacker run up to the hero while it winds up and walk back
/// once the blow has landed. Ranged enemies (a volley power) stay where they
/// are. Driven by [AttackWindup], so it needs `AutoCombatSystem.windupSeconds`
/// above zero; the blow itself lands when the run ends, which is exactly when
/// [AutoCombatSystem] applies it.
class LungeSystem extends System {
  LungeSystem({
    this.minGap = 22,
    this.maxGap = 58,
    this.runSeconds = 0.16,
    this.holdSeconds = 0.1,
    this.backSeconds = 0.2,
    math.Random? random,
  }) : _random = random ?? math.Random();

  /// How far in front of the hero (world units) the attacker stops: random
  /// between [minGap] and [maxGap] on every lunge, so a squad does not
  /// stack on one spot.
  final double minGap, maxGap;

  /// How long the run takes at most. It starts late enough to end exactly when
  /// the blow lands, so a long wind-up is spent waiting, then a quick dash.
  final double runSeconds;
  final math.Random _random;

  /// Time spent at the hero after the blow before turning back, and the time
  /// the walk back takes.
  final double holdSeconds;
  final double backSeconds;

  final _active = <EntityId, _Lunge>{};
  bool _listening = false;

  @override
  String get name => 'lunge';

  bool _ranged(World world, EntityId e) =>
      (world.componentsOf<EnemyPowers>().get(e)?.volleyEvery ?? 0) > 0;

  void _listen(World world) {
    _listening = true;
    world.events.on<AttackWindup>((w) {
      if (w.attackerSide != 'enemy' ||
          _active.containsKey(w.attacker) ||
          _ranged(world, w.attacker)) {
        return;
      }
      final positions = world.componentsOf<Position>();
      final here = positions.get(w.attacker);
      Position? hero;
      final roles = world.componentsOf<CombatRole>();
      for (var i = 0; i < roles.length; i++) {
        if (roles.denseAt(i).side == 'hero') {
          hero = positions.get(roles.entityAt(i));
        }
      }
      if (here == null || hero == null) return;
      final side = here.x >= hero.x ? 1.0 : -1.0;
      final gap = minGap + _random.nextDouble() * (maxGap - minGap);
      final run = math.min(runSeconds, w.seconds);
      _active[w.attacker] = _Lunge(
        here.x,
        hero.x + side * gap,
        w.seconds - run,
        run,
      );
    });
  }

  @override
  void update(World world, double dt) {
    if (!_listening) _listen(world);
    final positions = world.componentsOf<Position>();
    final health = world.componentsOf<Health>();
    for (final id in _active.keys.toList()) {
      final l = _active[id]!;
      final p = positions.get(id);
      if (p == null || (health.get(id)?.current ?? 1) <= 0) {
        _active.remove(id);
        continue;
      }
      l.t += dt;
      final runEnd = l.delay + l.outSeconds;
      final backStart = runEnd + holdSeconds;
      if (l.t < l.delay) {
        continue;
      } else if (l.t < runEnd) {
        p.x = l.home + (l.target - l.home) * ((l.t - l.delay) / l.outSeconds);
      } else if (l.t < backStart) {
        p.x = l.target;
      } else if (l.t < backStart + backSeconds) {
        p.x =
            l.target + (l.home - l.target) * ((l.t - backStart) / backSeconds);
      } else {
        p.x = l.home;
        _active.remove(id);
      }
    }
  }
}
