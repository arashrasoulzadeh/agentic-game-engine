import 'package:engine_core/engine_core.dart';

import 'rendering/animation.dart';
import 'rendering/animation_transition.dart';
import 'rendering/clip_shape.dart';
import 'rendering/hud_bar.dart';
import 'rendering/light2d.dart';
import 'rendering/nine_slice_sprite.dart';
import 'rendering/parallax_layer.dart';
import 'rendering/screen_tint.dart';
import 'rendering/sprite.dart';
import 'rendering/text.dart';
import 'input/input.dart';
import 'logic/scene_transition.dart';
import 'package:engine_schema/engine_schema.dart';

/// Registers engine_flutter's components on [world], mirroring
/// `registerCoreComponents`. `GameRunner` calls both automatically;
/// call this yourself only if you're wiring a `World` without `Game`.
void registerFlutterComponents(World world) {
  world.components.register<Sprite>(
    'sprite',
    (s) => s.toJson(),
    Sprite.fromJson,
    schema: spriteSchema,
  );
  world.components.register<AnimationState>(
    'animationState',
    (a) => a.toJson(),
    AnimationState.fromJson,
    schema: animationStateSchema,
  );
  world.components.register<InputState>(
    'inputState',
    (i) => i.toJson(),
    InputState.fromJson,
    schema: inputStateSchema,
  );
  world.components.register<ParallaxLayer>(
    'parallaxLayer',
    (p) => p.toJson(),
    ParallaxLayer.fromJson,
    schema: parallaxLayerSchema,
  );
  world.components.register<Text>(
    'text',
    (t) => t.toJson(),
    Text.fromJson,
    schema: textSchema,
  );
  world.components.register<HudBar>(
    'hudBar',
    (h) => h.toJson(),
    HudBar.fromJson,
    schema: hudBarSchema,
  );
  world.components.register<NineSliceSprite>(
    'nineSliceSprite',
    (n) => n.toJson(),
    NineSliceSprite.fromJson,
    schema: nineSliceSpriteSchema,
  );
  world.components.register<AnimationTransition>(
    'animationTransition',
    (a) => a.toJson(),
    AnimationTransition.fromJson,
    schema: animationTransitionSchema,
  );
  world.components.register<Light2D>(
    'light2d',
    (l) => l.toJson(),
    Light2D.fromJson,
    schema: light2dSchema,
  );
  world.components.register<ScreenTint>(
    'screenTint',
    (s) => s.toJson(),
    ScreenTint.fromJson,
    schema: screenTintSchema,
  );
  world.components.register<ClipShape>(
    'clipShape',
    (c) => c.toJson(),
    ClipShape.fromJson,
    schema: clipShapeSchema,
  );
  world.components.register<PlayerOptions>(
    'playerOptions',
    (o) => o.toJson(),
    PlayerOptions.fromJson,
    schema: playerOptionsSchema,
  );
  world.components.register<SceneTransition>(
    'sceneTransition',
    (s) => s.toJson(),
    SceneTransition.fromJson,
    schema: sceneTransitionSchema,
  );
}
