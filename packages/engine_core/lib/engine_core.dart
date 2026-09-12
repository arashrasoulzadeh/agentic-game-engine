export 'src/component_registry.dart';
export 'src/component_store.dart';
export 'src/components/collider.dart';
export 'src/components/position.dart';
export 'src/components/velocity.dart';
export 'src/entity.dart';
export 'src/event_bus.dart';
export 'src/spatial_hash.dart';
export 'src/system.dart';
export 'src/systems/collision_system.dart';
export 'src/systems/movement_system.dart';
export 'src/world.dart';

import 'src/components/collider.dart';
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
}
