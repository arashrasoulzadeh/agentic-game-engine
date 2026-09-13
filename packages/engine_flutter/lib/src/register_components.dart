import 'package:engine_core/engine_core.dart';

import 'rendering/animation.dart';
import 'rendering/hud_bar.dart';
import 'rendering/nine_slice_sprite.dart';
import 'rendering/parallax_layer.dart';
import 'rendering/sprite.dart';
import 'rendering/text.dart';
import 'input/input.dart';

/// Registers engine_flutter's components on [world], mirroring
/// `registerCoreComponents`. `GameRunner` calls both automatically;
/// call this yourself only if you're wiring a `World` without `Game`.
void registerFlutterComponents(World world) {
  world.components.register<Sprite>(
    'sprite',
    (s) => s.toJson(),
    Sprite.fromJson,
  );
  world.components.register<AnimationState>(
    'animationState',
    (a) => a.toJson(),
    AnimationState.fromJson,
  );
  world.components.register<InputState>(
    'inputState',
    (i) => i.toJson(),
    InputState.fromJson,
  );
  world.components.register<ParallaxLayer>(
    'parallaxLayer',
    (p) => p.toJson(),
    ParallaxLayer.fromJson,
  );
  world.components.register<Text>(
    'text',
    (t) => t.toJson(),
    Text.fromJson,
  );
  world.components.register<HudBar>(
    'hudBar',
    (h) => h.toJson(),
    HudBar.fromJson,
  );
  world.components.register<NineSliceSprite>(
    'nineSliceSprite',
    (n) => n.toJson(),
    NineSliceSprite.fromJson,
  );
}
