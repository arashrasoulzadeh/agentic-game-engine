import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;

import '../combat/combat_components.dart';

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

/// Subscribes [fx] to [FighterHit] events on [world].
void installCombatFx(World world, CombatFx fx, {double fxScale = 0.6}) {
  registerFxComponents(world);
  world.events.on<FighterHit>((hit) {
    final p = world.storeOf<Position>().get(hit.defender);
    if (p == null) return;
    final spark = fx.hit;
    if (spark != null) {
      spawnFx(world, spark, x: p.x, y: p.y - 8, scale: fxScale);
    }
    final slash = fx.slash;
    if (slash != null && hit.attackerSide == 'hero') {
      spawnFx(world, slash, x: p.x, y: p.y - 8, scale: fxScale);
    }
    final smoke = fx.death;
    if (smoke != null && hit.fatal) {
      spawnFx(world, smoke, x: p.x, y: p.y + 6, scale: fxScale);
    }
  });
}
