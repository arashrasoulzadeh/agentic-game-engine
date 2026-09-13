import 'package:engine_core/engine_core.dart';

import 'components/animation.dart';
import 'components/hud_bar.dart';
import 'components/parallax_layer.dart';
import 'components/sprite.dart';
import 'components/text.dart';
import 'input.dart';

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
}
