import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;
import 'package:zarvan_platformer/zarvan_platformer.dart';

/// Switches a fighter to its `death` state the moment its [Health] runs out.
/// Register before `SpriteStateSystem`; a scene then waits on
/// `spriteStateFinished(world, fighter, 'death')` before moving on.
class FighterDeathSystem extends System {
  @override
  String get name => 'fighterDeath';

  @override
  void update(World world, double dt) {
    final states = world.componentsOf<SpriteStates>();
    final health = world.componentsOf<Health>();
    for (var i = 0; i < states.length; i++) {
      final e = states.entityAt(i);
      final hp = health.get(e);
      if (hp != null && hp.current <= 0) playSpriteState(world, e, 'death');
    }
  }
}
