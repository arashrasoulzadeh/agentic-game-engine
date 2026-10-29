import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_platformer/engine_platformer.dart';

import 'combat_components.dart';

/// Spawns a fighter: [Sprite] + [AnimationState] + [Health] + [HitFlash].
///
/// [extraClips] (`attack`, `death`, …) add states beyond the looping `idle`
/// built from [atlasId]/[frameCount]; see [SpriteStateSystem].
EntityId spawnFighter(
  World world, {
  required String side,
  required double x,
  required double y,
  required double hp,
  required double attack,
  required double attackSpeed,
  required double armor,
  required String atlasId,
  required int frameCount,
  Map<String, SpriteClip> extraClips = const {},
  double scaleX = 1,
  double scaleY = 1,
  int zIndex = 10,
}) {
  final regions = [for (var i = 0; i < frameCount; i++) '$i'];
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(x, y));
  world.storeOf<Sprite>().set(
    id,
    Sprite(
      atlasId,
      regions.first,
      scaleX: scaleX,
      scaleY: scaleY,
      zIndex: zIndex,
    ),
  );
  world.storeOf<AnimationState>().set(
    id,
    AnimationState(
      AnimationClip('idle', regions, frameDurationSeconds: 0.15, loop: true),
    ),
  );
  world.storeOf<SpriteStates>().set(
    id,
    SpriteStates({
      'idle': SpriteClip(
        atlasId: atlasId,
        frames: frameCount,
        loop: true,
        frameSeconds: 0.15,
      ),
      ...extraClips,
    }),
  );
  world.storeOf<CombatRole>().set(id, CombatRole(side));
  world.storeOf<CombatStats>().set(
    id,
    CombatStats(
      maxHp: hp,
      attack: attack,
      attackSpeed: attackSpeed,
      armor: armor,
    ),
  );
  world.storeOf<Health>().set(id, Health(current: hp, max: hp));
  world.storeOf<HitFlash>().set(id, HitFlash());
  return id;
}
