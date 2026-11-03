import 'dart:math' as math;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart'
    show Camera, ScreenTint, Sprite;
import 'package:zarvan_platformer/zarvan_platformer.dart' show Health;

import 'damage_numbers.dart';

import '../combat/combat_components.dart';

/// How hitting and being hit feels. Pass to `WaveCombatConfig.hitFeedback`;
/// each part can be switched off with 0.
class HitFeedback {
  const HitFeedback({
    this.recoil = 3.5,
    this.recoilSeconds = 0.16,
    this.criticalRecoilScale = 1.8,
    this.heroHitFlashAlpha = 0.28,
    this.flashSeconds = 0.22,
    this.flashColorRgb = 0xD62828,
    this.shake = 1.2,
    this.criticalShake = 3.2,
    this.shakeSeconds = 0.14,
    this.criticalBurst = 10,
    this.hitStopSeconds = 0.07,
    this.heavyHitFraction = 0.25,
    this.windupTintArgb = 0xFFFFA040,
    this.windupWarning = true,
  });

  /// How far (world units) a fighter is knocked back when hit, for how long.
  /// A critical multiplies it by [criticalRecoilScale].
  final double recoil;
  final double recoilSeconds;
  final double criticalRecoilScale;

  /// Red screen flash when the hero is hit: peak alpha (0..1), seconds, colour.
  final double heroHitFlashAlpha;
  final double flashSeconds;
  final int flashColorRgb;

  /// Camera shake when the hero is hit / on any critical, and its duration.
  final double shake;
  final double criticalShake;
  final double shakeSeconds;

  /// Extra spark particles on a critical.
  final int criticalBurst;

  /// A brief freeze of combat and animation on a heavy hit (a critical, a
  /// killing blow, or one worth at least [heavyHitFraction] of the target's
  /// max health), so the blow lands visibly. 0 turns it off.
  final double hitStopSeconds;
  final double heavyHitFraction;

  /// Telegraph for an enemy's attack (see `AutoCombatSystem.windupSeconds`):
  /// the attacker glows this colour and a "!" appears over it. Alpha 0 / false
  /// turn the parts off.
  final int windupTintArgb;
  final bool windupWarning;
}

/// A fighter knocked back along x; the sprite springs back as it ends.
class HitRecoil {
  HitRecoil({
    required this.direction,
    required this.amplitude,
    required this.life,
    this.age = 0,
  });

  /// -1 or +1: away from the attacker.
  final double direction;
  final double amplitude;
  final double life;
  double age;

  Map<String, dynamic> toJson() => {
    'direction': direction,
    'amplitude': amplitude,
    'life': life,
    'age': age,
  };

  factory HitRecoil.fromJson(Map<String, dynamic> json) => HitRecoil(
    direction: (json['direction'] as num).toDouble(),
    amplitude: (json['amplitude'] as num).toDouble(),
    life: (json['life'] as num).toDouble(),
    age: (json['age'] as num?)?.toDouble() ?? 0,
  );
}

/// A fading flash on a `ScreenTint` entity.
class ScreenFlash {
  ScreenFlash({
    required this.rgb,
    required this.peak,
    required this.life,
    this.age = 0,
  });

  final int rgb;
  final double peak;
  final double life;
  double age;

  Map<String, dynamic> toJson() => {
    'rgb': rgb,
    'peak': peak,
    'life': life,
    'age': age,
  };

  factory ScreenFlash.fromJson(Map<String, dynamic> json) => ScreenFlash(
    rgb: json['rgb'] as int,
    peak: (json['peak'] as num).toDouble(),
    life: (json['life'] as num).toDouble(),
    age: (json['age'] as num?)?.toDouble() ?? 0,
  );
}

/// A fighter tinted until [remaining] runs out: the glow of an attack wind-up.
class WindupTint {
  WindupTint({required this.remaining});

  double remaining;

  Map<String, dynamic> toJson() => {'remaining': remaining};

  factory WindupTint.fromJson(Map<String, dynamic> json) =>
      WindupTint(remaining: (json['remaining'] as num).toDouble());
}

/// Freezes combat and animation for a moment. [freeze] pauses the named
/// systems; [update] (call it with the real frame time) resumes them.
class HitStop {
  HitStop(
    this.world, {
    this.systems = const ['autoCombat', 'animation', 'spriteState', 'movement'],
  });

  final World world;
  final List<String> systems;
  double _remaining = 0;

  bool get frozen => _remaining > 0;

  void freeze(double seconds) {
    if (seconds <= 0) return;
    if (!frozen) _set(false);
    _remaining = math.max(_remaining, seconds);
  }

  void update(double realDt) {
    if (!frozen) return;
    _remaining -= realDt;
    if (_remaining <= 0) {
      _remaining = 0;
      _set(true);
    }
  }

  void _set(bool enabled) {
    for (final name in systems) {
      if (world.systemOrder.contains(name)) {
        world.setSystemEnabled(name, enabled);
      }
    }
  }
}

/// Plays out [HitRecoil]s (as a sprite x-offset) and [ScreenFlash]es.
class HitFeedbackSystem extends System {
  @override
  String get name => 'hitFeedback';

  /// The tint each winding-up entity was given, so only that one is cleared.
  static final Map<EntityId, int> _windupColors = {};

  @override
  void update(World world, double dt) {
    final recoils = world.componentsOf<HitRecoil>();
    final sprites = world.componentsOf<Sprite>();
    final ended = <EntityId>[];
    for (var i = 0; i < recoils.length; i++) {
      final id = recoils.entityAt(i);
      final r = recoils.denseAt(i);
      r.age += dt;
      final sprite = sprites.get(id);
      if (r.age >= r.life) {
        sprite?.offsetX = 0;
        ended.add(id);
      } else if (sprite != null) {
        // Fast kick out, eased return.
        final t = r.age / r.life;
        sprite.offsetX =
            r.direction * r.amplitude * math.sin(math.pi * math.pow(t, 0.6));
      }
    }
    for (final id in ended) {
      recoils.remove(id);
    }

    final windups = world.componentsOf<WindupTint>();
    final windupEnded = <EntityId>[];
    for (var i = 0; i < windups.length; i++) {
      final id = windups.entityAt(i);
      final w = windups.denseAt(i);
      w.remaining -= dt;
      if (w.remaining <= 0) {
        windupEnded.add(id);
        final sprite = sprites.get(id);
        if (sprite != null && sprite.tintArgb == _windupColors[id]) {
          sprite.tintArgb = null;
        }
        _windupColors.remove(id);
      }
    }
    for (final id in windupEnded) {
      windups.remove(id);
    }

    final flashes = world.componentsOf<ScreenFlash>();
    final tints = world.componentsOf<ScreenTint>();
    for (var i = 0; i < flashes.length; i++) {
      final id = flashes.entityAt(i);
      final f = flashes.denseAt(i);
      f.age = math.min(f.age + dt, f.life);
      final alpha = f.peak * (1 - f.age / f.life);
      final tint = tints.get(id);
      if (tint != null) {
        tint.colorArgb = (f.rgb & 0xFFFFFF) | ((alpha * 255).round() << 24);
      }
    }
  }
}

/// Wires [feedback] to [FighterHit] events: knockback on the fighter that was
/// hit, a red flash and camera shake when the hero is hit, and a bigger shake
/// and extra sparks on criticals. Needs [HitFeedbackSystem] in the world.
void installHitFeedback(
  World world,
  HitFeedback feedback,
  Camera camera, {
  HitStop? hitStop,
  DamageNumberStyle warningStyle = const DamageNumberStyle(),
}) {
  final flashEntity = world.spawn();
  world.componentsOf<ScreenTint>().set(flashEntity, ScreenTint(0));
  world.componentsOf<ScreenFlash>().set(
    flashEntity,
    ScreenFlash(
      rgb: feedback.flashColorRgb,
      peak: feedback.heroHitFlashAlpha,
      life: feedback.flashSeconds,
      age: feedback.flashSeconds,
    ),
  );

  world.events.on<AttackWindup>((w) {
    if (w.attackerSide == 'hero') return; // telegraph the enemy's blows
    final sprite = world.componentsOf<Sprite>().get(w.attacker);
    if (sprite != null && feedback.windupTintArgb >>> 24 != 0) {
      sprite.tintArgb = feedback.windupTintArgb;
      HitFeedbackSystem._windupColors[w.attacker] = feedback.windupTintArgb;
      world.componentsOf<WindupTint>().set(
        w.attacker,
        WindupTint(remaining: w.seconds),
      );
    }
    final pos = world.componentsOf<Position>().get(w.attacker);
    if (feedback.windupWarning && pos != null) {
      spawnFloatingText(
        world,
        '!',
        pos.x,
        pos.y - 28,
        size: warningStyle.baseSize * 1.6,
        colorArgb: 0xFFFF3B30,
        style: warningStyle,
        popScale: 1.7,
        life: w.seconds + 0.12,
        rise: 0,
      );
    }
  });

  world.events.on<FighterHit>((hit) {
    final positions = world.componentsOf<Position>();
    final from = positions.get(hit.attacker);
    final to = positions.get(hit.defender);
    final heroHit = hit.attackerSide != 'hero';

    if (feedback.recoil > 0 && from != null && to != null && !hit.fatal) {
      world.componentsOf<HitRecoil>().set(
        hit.defender,
        HitRecoil(
          direction: from.x < to.x ? 1 : -1,
          amplitude:
              feedback.recoil *
              (hit.critical ? feedback.criticalRecoilScale : 1),
          life: feedback.recoilSeconds,
        ),
      );
    }
    if (heroHit && feedback.heroHitFlashAlpha > 0) {
      world.componentsOf<ScreenFlash>().get(flashEntity)?.age = 0;
    }
    final magnitude = hit.critical
        ? feedback.criticalShake
        : heroHit
        ? feedback.shake
        : 0.0;
    if (magnitude > 0) {
      camera.shake(
        magnitude: magnitude,
        duration: feedback.shakeSeconds,
        impulse: true,
      );
    }
    if (hitStop != null && feedback.hitStopSeconds > 0) {
      final maxHp = world.componentsOf<Health>().get(hit.defender)?.max ?? 1;
      if (hit.critical ||
          hit.fatal ||
          hit.damage >= maxHp * feedback.heavyHitFraction) {
        hitStop.freeze(feedback.hitStopSeconds);
      }
    }
    if (hit.critical && feedback.criticalBurst > 0) {
      world.componentsOf<ParticleEmitter>().get(hit.defender)?.burstCount +=
          feedback.criticalBurst;
    }
  });
}

/// Registers the components of [HitFeedbackSystem] (including the attack
/// wind-up tint) so they serialize.
void registerHitFeedbackComponents(World world) {
  registerWindupComponents(world);
  if (world.components.isRegistered('hitRecoil')) return;
  world.components.register<HitRecoil>(
    'hitRecoil',
    (c) => c.toJson(),
    HitRecoil.fromJson,
  );
  world.components.register<ScreenFlash>(
    'screenFlash',
    (c) => c.toJson(),
    ScreenFlash.fromJson,
  );
}

/// Registers [WindupTint] so it serializes.
void registerWindupComponents(World world) {
  if (world.components.isRegistered('windupTint')) return;
  world.components.register<WindupTint>(
    'windupTint',
    (c) => c.toJson(),
    WindupTint.fromJson,
  );
}
