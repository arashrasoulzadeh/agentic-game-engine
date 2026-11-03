/// The small set of zarvan_core you reach for every day: build a world, spawn
/// entities, read and write components, load levels, react to events, test.
///
/// `package:zarvan_core/zarvan_core.dart` exports everything (every system,
/// every genre rule, the content pipeline); import this instead when you want an
/// editor's autocomplete to stay readable, and add the full barrel (or one of the
/// topic barrels: `zarvan_core_idle`, `zarvan_core_ops`, `zarvan_core_testing`)
/// only where you need more. Everything here is the same type as in the full
/// barrel, so the two can be mixed freely.
library;

export 'src/ecs/engine_error.dart';
export 'src/ecs/behavior.dart' show Behavior, BehaviorRegistry;
export 'src/ecs/action.dart';
export 'src/ecs/entity.dart';
export 'src/ecs/entity_builder.dart';
export 'src/ecs/entity_handle.dart';
export 'src/ecs/event_bus.dart';
export 'src/ecs/game_builder.dart';
export 'src/ecs/name.dart';
export 'src/ecs/register_core_components.dart';
export 'src/ecs/tags.dart';
export 'src/ecs/world.dart';
export 'src/ecs/world_commands.dart';
export 'src/ecs/world_query.dart';
export 'src/ecs/world_timers.dart' show TimerHandle;
export 'src/ecs/world_view.dart';
export 'src/content/level.dart';
export 'src/content/prefab_registry.dart';
export 'src/physics/collider.dart';
export 'src/physics/position.dart';
export 'src/physics/velocity.dart';
export 'src/physics/world_movement.dart';
export 'src/physics/world_spatial.dart';
