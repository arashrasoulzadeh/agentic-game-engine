import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_platformer/engine_platformer.dart';

/// Switches a fighter to its `death` state the moment its [Health] runs out.
/// Register before `SpriteStateSystem`; a scene then waits on
/// `spriteStateFinished(world, fighter, 'death')` before moving on.
class FighterDeathSystem extends System {
  @override
  String get name => 'fighterDeath';

  @override
  void update(World world, double dt) {
    final states = world.storeOf<SpriteStates>();
    final health = world.storeOf<Health>();
    for (var i = 0; i < states.length; i++) {
      final e = states.entityAt(i);
      final hp = health.get(e);
      if (hp != null && hp.current <= 0) playSpriteState(world, e, 'death');
    }
  }
}
