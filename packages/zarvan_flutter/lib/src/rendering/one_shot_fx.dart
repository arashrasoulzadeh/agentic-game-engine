import 'package:zarvan_core/zarvan_core.dart';

import 'animation.dart';
import 'sprite.dart';

/// Marks a fire-and-forget effect entity; [OneShotFxSystem] removes it once
/// its clip has played.
class OneShotFx {
  OneShotFx();

  Map<String, dynamic> toJson() => const {};
  factory OneShotFx.fromJson(Map<String, dynamic> json) => OneShotFx();
}

/// An effect sheet: atlas id, frame count and pace.
class FxClip {
  const FxClip(this.atlasId, this.frames, {this.frameSeconds = 0.07});
  final String atlasId;
  final int frames;
  final double frameSeconds;
}

/// Plays [clip] once, centred at ([x], [y]); [OneShotFxSystem] cleans it up.
EntityId spawnFx(
  World world,
  FxClip clip, {
  required double x,
  required double y,
  double scale = 1,
  int zIndex = 30,
}) {
  final id = world.spawn();
  world.componentsOf<Position>().set(id, Position(x, y));
  world.componentsOf<Sprite>().set(
    id,
    Sprite(clip.atlasId, '0', scaleX: scale, scaleY: scale, zIndex: zIndex),
  );
  world.componentsOf<AnimationState>().set(
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
  world.componentsOf<OneShotFx>().set(id, OneShotFx());
  return id;
}

/// Destroys [OneShotFx] entities whose clip has finished. Register after
/// `AnimationSystem`.
class OneShotFxSystem extends System {
  @override
  String get name => 'oneShotFx';

  @override
  void update(World world, double dt) {
    final fx = world.componentsOf<OneShotFx>();
    final anims = world.componentsOf<AnimationState>();
    final done = <EntityId>[
      for (var i = 0; i < fx.length; i++)
        if (!(anims.get(fx.entityAt(i))?.playing ?? false)) fx.entityAt(i),
    ];
    for (final e in done) {
      world.destroy(e);
    }
  }
}
