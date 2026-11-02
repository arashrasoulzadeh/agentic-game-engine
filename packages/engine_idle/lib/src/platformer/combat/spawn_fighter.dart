import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_platformer/engine_platformer.dart';

import 'combat_components.dart';

/// Spawns a fighter: [Sprite] + [AnimationState] + [Health] + [HitFlash].
///
/// [extraClips] (`attack`, `death`, …) add states beyond the looping `idle`
/// built from [atlasId]/[frameCount]; see [SpriteStateSystem].
/// [impactParticles] gives the fighter an emitter that hits and `particle`
/// animation cues burst from (needs `ParticleSystem` in the world).
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
  ParticleEmitter? impactParticles,
  double scaleX = 1,
  double scaleY = 1,
  int zIndex = 10,
}) {
  final regions = [for (var i = 0; i < frameCount; i++) '$i'];
  final id = world.spawn();
  world.componentsOf<Position>().set(id, Position(x, y));
  world.componentsOf<Sprite>().set(
    id,
    Sprite(
      atlasId,
      regions.first,
      scaleX: scaleX,
      scaleY: scaleY,
      zIndex: zIndex,
    ),
  );
  world.componentsOf<AnimationState>().set(
    id,
    AnimationState(
      AnimationClip('idle', regions, frameDurationSeconds: 0.15, loop: true),
    ),
  );
  world.componentsOf<SpriteStates>().set(
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
  if (impactParticles != null) {
    world.componentsOf<ParticleEmitter>().set(id, impactParticles);
  }
  world.componentsOf<CombatRole>().set(id, CombatRole(side));
  world.componentsOf<CombatStats>().set(
    id,
    CombatStats(
      maxHp: hp,
      attack: attack,
      attackSpeed: attackSpeed,
      armor: armor,
    ),
  );
  world.componentsOf<Health>().set(id, Health(current: hp, max: hp));
  world.componentsOf<HitFlash>().set(id, HitFlash());
  return id;
}
