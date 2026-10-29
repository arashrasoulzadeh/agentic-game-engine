import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;

import '../fighters/pivots.dart';

import '../combat/combat_components.dart';
import '../combat/fighter_anims.dart';

/// Marks a one-shot effect entity; [FxSystem] removes it once its clip ends.
class FxLife {
  FxLife();

  Map<String, dynamic> toJson() => const {};
  factory FxLife.fromJson(Map<String, dynamic> json) => FxLife();
}

void registerFxComponents(World world) {
  if (world.components.isRegistered('fxLife')) return;
  world.components.register<FxLife>(
    'fxLife',
    (c) => c.toJson(),
    FxLife.fromJson,
  );
}

/// An effect sheet: atlas id plus its frame count.
class FxClip {
  const FxClip(this.atlasId, this.frames, {this.frameSeconds = 0.07});
  final String atlasId;
  final int frames;
  final double frameSeconds;
}

/// Plays [clip] once at ([x], [y]) and lets [FxSystem] clean it up.
EntityId spawnFx(
  World world,
  FxClip clip, {
  required double x,
  required double y,
  double scale = 1,
  int zIndex = 30,
}) {
  registerFxComponents(world);
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(x, y));
  world.storeOf<Sprite>().set(
    id,
    Sprite(clip.atlasId, '0', scaleX: scale, scaleY: scale, zIndex: zIndex),
  );
  world.storeOf<AnimationState>().set(
    id,
    AnimationState(
      AnimationClip(
        'fx',
        [for (var i = 0; i < clip.frames; i++) '$i'],
        frameDurationSeconds: clip.frameSeconds,
        loop: false,
      ),
    ),
  );
  world.storeOf<FxLife>().set(id, FxLife());
  return id;
}

/// Destroys effects whose clip has finished. Register after `AnimationSystem`.
class FxSystem extends System {
  @override
  String get name => 'fx';

  @override
  void update(World world, double dt) {
    final life = world.storeOf<FxLife>();
    final states = world.storeOf<AnimationState>();
    final done = <EntityId>[
      for (var i = 0; i < life.length; i++)
        if (!(states.get(life.entityAt(i))?.playing ?? false)) life.entityAt(i),
    ];
    for (final e in done) {
      world.destroy(e);
    }
  }
}

/// Which effect plays for which combat moment. Any may be omitted.
class CombatFx {
  const CombatFx({this.hit, this.slash, this.death});

  /// Spark on the defender for every hit.
  final FxClip? hit;

  /// Swing flash on the defender when the *hero* strikes.
  final FxClip? slash;

  /// Smoke at the feet of a fighter that just fell.
  final FxClip? death;
}

/// Opaque pixels of an effect sheet's art, so a scale of 1 reads as "one
/// body-height wide" rather than "one 64px cell wide".
const _fxArtPixels = 48.0;

/// Subscribes [fx] to [FighterHit] events on [world].
///
/// With [pivots], effects are sized and placed from the defender's real
/// silhouette: sparks at chest height on the side the blow came from, smoke
/// at the feet. Without it they fall back to the entity's centre.
void installCombatFx(World world, CombatFx fx, {PivotTable? pivots}) {
  registerFxComponents(world);
  world.events.on<FighterHit>((hit) {
    final pos = world.storeOf<Position>();
    final p = pos.get(hit.defender);
    final from = pos.get(hit.attacker);
    final sprite = world.storeOf<Sprite>().get(hit.defender);
    final anims = world.storeOf<FighterAnims>().get(hit.defender);
    if (p == null || sprite == null) return;

    final body = anims == null
        ? null
        : pivots?.bodyOf(anims.clips['idle']?.atlasId ?? '');
    final s = sprite.scaleX;
    // World-space feet, silhouette height, and the side facing the attacker.
    final feetX = body == null ? p.x : p.x + (body.x - body.cell / 2) * s;
    final feetY = body == null
        ? p.y + 16
        : p.y + (body.bottom - body.cell / 2) * s;
    final height = body == null ? 48.0 : (body.bottom - body.top) * s;
    final side = from == null || from.x == p.x
        ? 0.0
        : (from.x < p.x ? -1.0 : 1.0);

    double scaleFor(double bodyFraction) =>
        height * bodyFraction / _fxArtPixels;

    final spark = fx.hit;
    if (spark != null) {
      spawnFx(
        world,
        spark,
        x: feetX + side * height * 0.12,
        y: feetY - height * 0.6,
        scale: scaleFor(0.3),
      );
    }
    final slash = fx.slash;
    if (slash != null && hit.attackerSide == 'hero') {
      spawnFx(
        world,
        slash,
        x: feetX + side * height * 0.1,
        y: feetY - height * 0.55,
        scale: scaleFor(0.85),
      );
    }
    final smoke = fx.death;
    if (smoke != null && hit.fatal) {
      spawnFx(
        world,
        smoke,
        x: feetX,
        y: feetY - height * 0.25,
        scale: scaleFor(0.9),
      );
    }
  });
}
