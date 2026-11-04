import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_platformer/zarvan_platformer.dart';

import 'combat/combat_components.dart';
import 'fx/damage_numbers.dart';
import 'fx/hit_feedback.dart';

/// Registers every component a wave-combat scene uses beyond the core and
/// Flutter ones, so a world built for it serializes completely. One call, so a
/// scene cannot forget one of the pieces (an unregistered component silently
/// drops out of `World.toJson`).
void registerWaveCombatComponents(World world) {
  registerPlatformerComponents(world);
  registerCombatComponents(world);
  registerDamageNumberComponents(world);
  registerHitFeedbackComponents(world);
}
