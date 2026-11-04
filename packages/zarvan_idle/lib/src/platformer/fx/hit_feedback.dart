import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart'
    show Camera, ScreenTint, Sprite;
import 'package:zarvan_platformer/zarvan_platformer.dart' show Health;

import '../combat/combat_components.dart';
import 'damage_numbers.dart';
import 'hit_components.dart';
import 'hit_stop.dart';

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
      world.componentsOf<WindupTint>().set(
        w.attacker,
        WindupTint(remaining: w.seconds, tintArgb: feedback.windupTintArgb),
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
