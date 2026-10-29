import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;

import '../combat/combat_components.dart';

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
  world.events.on<FighterHit>((hit) {
    final pos = world.storeOf<Position>();
    final p = pos.get(hit.defender);
    final from = pos.get(hit.attacker);
    final sprite = world.storeOf<Sprite>().get(hit.defender);
    final states = world.storeOf<SpriteStates>().get(hit.defender);
    if (p == null || sprite == null) return;

    final body = states == null
        ? null
        : pivots?.bodyOf(states.clips[states.restState]?.atlasId ?? '');
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
