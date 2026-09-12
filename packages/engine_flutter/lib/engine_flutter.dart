export 'src/camera.dart';
export 'src/components/animation.dart';
export 'src/components/sprite.dart';
export 'src/engine_view.dart';
export 'src/input.dart';
export 'src/sprite_atlas.dart';
export 'src/systems/animation_system.dart';

import 'package:engine_core/engine_core.dart';

import 'src/components/animation.dart';
import 'src/components/sprite.dart';
import 'src/input.dart';

/// Registers engine_flutter's components on [world], mirroring
/// `registerCoreComponents`. Call alongside it: `registerCoreComponents(world);
/// registerFlutterComponents(world);`.
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
}
