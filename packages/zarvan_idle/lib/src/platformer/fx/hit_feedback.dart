import 'dart:math' as math;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart'
    show Camera, ScreenTint, Sprite;

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

/// Plays out [HitRecoil]s (as a sprite x-offset) and [ScreenFlash]es.
class HitFeedbackSystem extends System {
  @override
  String get name => 'hitFeedback';

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
void installHitFeedback(World world, HitFeedback feedback, Camera camera) {
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
    if (hit.critical && feedback.criticalBurst > 0) {
      world.componentsOf<ParticleEmitter>().get(hit.defender)?.burstCount +=
          feedback.criticalBurst;
    }
  });
}

/// Registers the components of [HitFeedbackSystem] so they serialize.
void registerHitFeedbackComponents(World world) {
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
