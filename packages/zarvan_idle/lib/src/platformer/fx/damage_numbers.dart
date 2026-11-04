import 'dart:math' as math;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' as eng show Text;

import 'package:zarvan_platformer/zarvan_platformer.dart' show Health;

import '../combat/combat_components.dart';
import '../combat/conditions.dart';
import '../hud/world_text.dart';

/// How floating damage numbers look. Pass to `WaveCombatConfig.damageNumbers`.
class DamageNumberStyle {
  const DamageNumberStyle({
    this.lifetime = 1.0,
    this.riseSpeed = 34,
    this.baseSize = 11,
    this.maxBigScale = 2.2,
    this.criticalScale = 1.7,
    this.popScale = 1.8,
    this.popSeconds = 0.18,
    this.drift = 14,
    this.shadowColorArgb = 0xFF1A0B00,
    this.tierColorsArgb = const [
      0xFFFFFFFF, // a nick
      0xFFFFE066, // light
      0xFFFF9F1C, // solid
      0xFFFF4D2E, // heavy
    ],
    this.criticalColorArgb = 0xFFFFC93C,
    this.enemyHitColorArgb = 0xFFFF5A4D,
    this.dodgeColorArgb = 0xFF7FDBFF,
    this.bleedColorArgb = 0xFFB3201B,
    this.poisonColorArgb = 0xFF7CD13C,
    this.dodgeText = 'Dodge',
  });

  /// Seconds a number stays up while it rises and fades.
  final double lifetime;

  /// World units per second it rises at the start (it slows as it fades).
  final double riseSpeed;

  /// Font size of an ordinary hit.
  final double baseSize;

  /// A hit worth a whole health bar draws up to this many times [baseSize]:
  /// the scale grows with damage relative to the target's max health.
  final double maxBigScale;

  /// Extra size multiplier for a critical hit.
  final double criticalScale;

  /// The number appears this many times larger and settles to size over
  /// [popSeconds]; criticals pop a little harder.
  final double popScale;
  final double popSeconds;

  /// Sideways drift in world units per second (random direction per number).
  final double drift;

  /// Colour of the dark copy drawn just behind each number so it reads on any
  /// background.
  final int shadowColorArgb;

  /// Colours for the hero's hits from light to heavy, picked by the damage as
  /// a fraction of the target's max health (under 8%, 8-20%, 20-45%, more).
  final List<int> tierColorsArgb;

  /// A critical, and an enemy hitting the hero.
  final int criticalColorArgb;
  final int enemyHitColorArgb;

  /// The colour of a dodged hit's text and its wording.
  final int dodgeColorArgb;
  final String dodgeText;

  /// Damage-over-time numbers: bleed and poison.
  final int bleedColorArgb;
  final int poisonColorArgb;

  /// The colour for a hero hit worth [fraction] of the target's max health.
  int tierColor(double fraction) {
    final tiers = tierColorsArgb;
    final i = fraction < 0.08
        ? 0
        : fraction < 0.2
        ? 1
        : fraction < 0.45
        ? 2
        : 3;
    return tiers[math.min(i, tiers.length - 1)];
  }
}

/// A floating number's animation state, stored on the entity that carries its
/// `Text`. Serializable like every component.
class DamageNumber {
  DamageNumber({
    required this.life,
    required this.riseSpeed,
    required this.colorArgb,
    this.popScale = 1,
    this.popSeconds = 0.15,
    this.driftX = 0,
    this.age = 0,
  });

  final double life;
  final double riseSpeed;

  /// Full-opacity colour; the system fades its alpha over [life].
  final int colorArgb;

  /// Starts [popScale] times larger and settles to 1 over [popSeconds].
  final double popScale;
  final double popSeconds;

  /// Sideways speed in world units per second.
  final double driftX;
  double age;

  Map<String, dynamic> toJson() => {
    'life': life,
    'riseSpeed': riseSpeed,
    'colorArgb': colorArgb,
    'popScale': popScale,
    'popSeconds': popSeconds,
    'driftX': driftX,
    'age': age,
  };

  factory DamageNumber.fromJson(Map<String, dynamic> json) => DamageNumber(
    life: (json['life'] as num).toDouble(),
    riseSpeed: (json['riseSpeed'] as num).toDouble(),
    colorArgb: json['colorArgb'] as int,
    popScale: (json['popScale'] as num?)?.toDouble() ?? 1,
    popSeconds: (json['popSeconds'] as num?)?.toDouble() ?? 0.15,
    driftX: (json['driftX'] as num?)?.toDouble() ?? 0,
    age: (json['age'] as num?)?.toDouble() ?? 0,
  );
}

/// Pops, rises, drifts, fades and finally removes every [DamageNumber].
class DamageNumberSystem extends System {
  @override
  String get name => 'damageNumbers';

  @override
  void update(World world, double dt) {
    final numbers = world.componentsOf<DamageNumber>();
    final texts = world.componentsOf<eng.Text>();
    final positions = world.componentsOf<Position>();
    final done = <EntityId>[];
    for (var i = 0; i < numbers.length; i++) {
      final id = numbers.entityAt(i);
      final n = numbers.denseAt(i);
      n.age += dt;
      final t = (n.age / n.life).clamp(0.0, 1.0);
      if (t >= 1) {
        done.add(id);
        continue;
      }
      // Rise fast, then ease out; stay opaque for the first half, then fade.
      final p = positions.get(id);
      if (p != null) {
        p.y -= n.riseSpeed * (1 - t) * dt;
        p.x += n.driftX * (1 - t) * dt;
      }
      final alpha = t < 0.5 ? 1.0 : 1 - (t - 0.5) / 0.5;
      final text = texts.get(id);
      if (text != null) {
        text.colorArgb =
            (n.colorArgb & 0x00FFFFFF) | ((alpha * 255).round() << 24);
        final pop = (1 - n.age / n.popSeconds).clamp(0.0, 1.0);
        text.textScale = 1 + (n.popScale - 1) * pop * pop;
      }
    }
    for (final id in done) {
      world.destroy(id);
    }
  }
}

/// Spawns a floating number over a fighter on every [FighterHit].
///
/// Bigger hits (relative to the target's max health) and criticals draw
/// larger; criticals are gold and end in `!`.
void installDamageNumbers(World world, DamageNumberStyle style) {
  world.events.on<FighterHit>((hit) {
    final pos = world.componentsOf<Position>().get(hit.defender);
    if (pos == null) return;
    final maxHp = world.componentsOf<Health>().get(hit.defender)?.max ?? 1;
    final fraction = (hit.damage / math.max(1, maxHp)).clamp(0.0, 1.0);
    var size = style.baseSize * (1 + (style.maxBigScale - 1) * fraction);
    if (hit.critical) size *= style.criticalScale;
    final color = hit.critical
        ? style.criticalColorArgb
        : hit.attackerSide == 'hero'
        ? style.tierColor(fraction)
        : style.enemyHitColorArgb;
    spawnFloatingText(
      world,
      '${hit.damage.round()}${hit.critical ? '!' : ''}',
      pos.x + world.random.nextDouble() * 12 - 6,
      pos.y - 24,
      size: size,
      colorArgb: color,
      style: style,
      popScale: hit.critical ? style.popScale * 1.25 : style.popScale,
      drift: (world.random.nextDouble() * 2 - 1) * style.drift,
    );
  });
  world.events.on<ConditionTick>((tick) {
    final pos = world.componentsOf<Position>().get(tick.entity);
    if (pos == null || tick.damage < 0.5) return;
    spawnFloatingText(
      world,
      tick.damage.round().toString(),
      pos.x + world.random.nextDouble() * 10 - 5,
      pos.y - 10,
      size: style.baseSize * 0.8,
      colorArgb: tick.kind == ConditionKind.poison
          ? style.poisonColorArgb
          : style.bleedColorArgb,
      style: style,
      life: 0.7,
      popScale: 1,
    );
  });
  world.events.on<FighterDodge>((dodge) {
    final pos = world.componentsOf<Position>().get(dodge.defender);
    if (pos == null) return;
    spawnFloatingText(
      world,
      style.dodgeText,
      pos.x,
      pos.y - 24,
      size: style.baseSize * 1.1,
      colorArgb: style.dodgeColorArgb,
      style: style,
    );
  });
}

/// Spawns [text] at ([x], [y]) as a floating number: a dark copy behind a
/// coloured one, both animated by [DamageNumberSystem]. [life] and [rise]
/// default to the [style]'s.
void spawnFloatingText(
  World world,
  String text,
  double x,
  double y, {
  required double size,
  required int colorArgb,
  required DamageNumberStyle style,
  double? popScale,
  double drift = 0,
  double? life,
  double? rise,
}) {
  void spawn(double dx, double dy, int argb, int z) {
    final id = spawnWorldText(
      world,
      x + dx,
      y + dy,
      text,
      fontSize: size,
      colorArgb: argb,
      zIndex: z,
    );
    world.componentsOf<DamageNumber>().set(
      id,
      DamageNumber(
        life: life ?? style.lifetime,
        riseSpeed: rise ?? style.riseSpeed,
        colorArgb: argb,
        popScale: popScale ?? style.popScale,
        popSeconds: style.popSeconds,
        driftX: drift,
      ),
    );
  }

  // The dark copy first (behind), then the coloured number on top.
  spawn(size * 0.07, size * 0.07, style.shadowColorArgb, 129);
  spawn(0, 0, colorArgb, 130);
}

/// Registers [DamageNumber] so it serializes.
void registerDamageNumberComponents(World world) {
  if (world.components.isRegistered('damageNumber')) return;
  world.components.register<DamageNumber>(
    'damageNumber',
    (c) => c.toJson(),
    DamageNumber.fromJson,
  );
}
