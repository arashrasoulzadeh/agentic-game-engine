export 'src/action.dart';
export 'src/actions/set_velocity_action.dart';
export 'src/behavior.dart';
export 'src/component_registry.dart';
export 'src/component_store.dart';
export 'src/components/ai_state.dart';
export 'src/components/collider.dart';
export 'src/components/gravity.dart';
export 'src/components/platform_body.dart';
export 'src/components/platformer_controller.dart';
export 'src/components/position.dart';
export 'src/components/velocity.dart';
export 'src/entity.dart';
export 'src/event_bus.dart';
export 'src/level.dart';
export 'src/spatial_hash.dart';
export 'src/system.dart';
export 'src/systems/ai_system.dart';
export 'src/systems/collision_system.dart';
export 'src/systems/gravity_system.dart';
export 'src/systems/movement_system.dart';
export 'src/systems/platformer_system.dart';
export 'src/world.dart';
export 'src/world_view.dart';

import 'src/components/ai_state.dart';
import 'src/components/collider.dart';
import 'src/components/gravity.dart';
import 'src/components/platform_body.dart';
import 'src/components/platformer_controller.dart';
import 'src/components/position.dart';
import 'src/components/velocity.dart';
import 'src/world.dart';

/// Registers the engine's built-in components on [world]. Games/agents
/// register their own additional component types the same way via
/// `world.components.register<T>(...)`.
void registerCoreComponents(World world) {
  world.components.register<Position>(
    'position',
    (p) => p.toJson(),
    Position.fromJson,
  );
  world.components.register<Velocity>(
    'velocity',
    (v) => v.toJson(),
    Velocity.fromJson,
  );
  world.components.register<Collider>(
    'collider',
    (c) => c.toJson(),
    Collider.fromJson,
  );
  world.components.register<AIState>(
    'aiState',
    (a) => a.toJson(),
    AIState.fromJson,
  );
  world.components.register<Gravity>(
    'gravity',
    (g) => g.toJson(),
    Gravity.fromJson,
  );
  world.components.register<PlatformBody>(
    'platformBody',
    (p) => p.toJson(),
    PlatformBody.fromJson,
  );
  world.components.register<PlatformerController>(
    'platformerController',
    (p) => p.toJson(),
    PlatformerController.fromJson,
  );
}
