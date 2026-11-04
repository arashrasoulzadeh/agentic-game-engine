import 'dart:math' as math;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;

import 'sun_light.dart';

/// What a [SceneLight] is attached to.
enum LightAnchor {
  /// Fixed at its own `x`/`y`.
  none,

  /// Follows the hero; `x`/`y` is an offset from the hero's position.
  hero,

  /// Follows the current enemy (and is off while there is none).
  enemy,
}

/// A light in a wave-combat scene: a lantern on the hero, a glow on the
/// enemy, a torch on the ground. Listed in `WaveCombatConfig.lights`.
class SceneLight {
  const SceneLight({
    this.anchor = LightAnchor.none,
    this.x = 0,
    this.y = 0,
    this.radius = 40,
    this.intensity = 0.6,
    this.colorArgb = 0x26FFB347,
    this.flicker = 0,
    this.flickerHz = 7,
  });

  final LightAnchor anchor;

  /// World position, or the offset from the anchor.
  final double x;
  final double y;
  final double radius;

  /// `Light2D.intensity` (0..1).
  final double intensity;

  /// Additive tint as ARGB; alpha 0 gives plain light with no colour.
  final int colorArgb;

  /// How far the radius wobbles, as a fraction of [radius] (0 = steady), at
  /// [flickerHz]: torch and lantern flames.
  final double flicker;
  final double flickerHz;
}

/// Spawns the sun (if any) and every [SceneLight] of a scene, and adds the
/// [SceneLightSystem] that moves them. [heroOf]/[enemyOf] resolve the anchors.
void installSceneLights(
  World world, {
  SunLight? sun,
  List<SceneLight> lights = const [],
  required EntityId? Function() heroOf,
  required EntityId? Function() enemyOf,
}) {
  EntityId spawnLight(double x, double y, Light2D light) {
    final id = world.spawn();
    world.componentsOf<Position>().set(id, Position(x, y));
    world.componentsOf<Light2D>().set(id, light);
    return id;
  }

  if (sun != null) {
    spawnLight(
      sun.x,
      sun.y,
      Light2D(
        radius: sun.radius,
        intensity: sun.intensity,
        colorArgb: sun.colorArgb,
      ),
    );
  }
  if (lights.isEmpty) return;
  final ids = [
    for (final l in lights)
      spawnLight(
        l.x,
        l.y,
        Light2D(
          radius: l.radius,
          intensity: l.intensity,
          colorArgb: l.colorArgb,
        ),
      ),
  ];
  world.addSystem(SceneLightSystem(lights, ids, heroOf, enemyOf));
}

/// Moves the lights of `WaveCombatConfig.lights` to their anchors and flickers
/// them. One entity per light, in [entities], matching [lights] by index.
class SceneLightSystem extends System {
  SceneLightSystem(this.lights, this.entities, this.heroOf, this.enemyOf);

  final List<SceneLight> lights;
  final List<EntityId> entities;
  final EntityId? Function() heroOf;
  final EntityId? Function() enemyOf;
  double _time = 0;

  @override
  String get name => 'SceneLightSystem';

  @override
  void update(World world, double dt) {
    _time += dt;
    final positions = world.componentsOf<Position>();
    final lightStore = world.componentsOf<Light2D>();
    for (var i = 0; i < lights.length; i++) {
      final spec = lights[i];
      final light = lightStore.get(entities[i]);
      final pos = positions.get(entities[i]);
      if (light == null || pos == null) continue;
      switch (spec.anchor) {
        case LightAnchor.none:
          pos
            ..x = spec.x
            ..y = spec.y;
          light.radius = _wobble(spec, i);
        case LightAnchor.hero:
        case LightAnchor.enemy:
          final target = spec.anchor == LightAnchor.hero ? heroOf() : enemyOf();
          final at = target == null || !world.entities.isAlive(target)
              ? null
              : positions.get(target);
          if (at == null) {
            light.radius = 0; // no target: the light is off
          } else {
            pos
              ..x = at.x + spec.x
              ..y = at.y + spec.y;
            light.radius = _wobble(spec, i);
          }
      }
    }
  }

  double _wobble(SceneLight spec, int i) =>
      spec.radius *
      (1 +
          spec.flicker *
              math.sin(_time * spec.flickerHz * 2 * math.pi + i * 1.7));
}
