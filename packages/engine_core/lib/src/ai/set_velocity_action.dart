import '../ecs/action.dart';
import '../physics/velocity.dart';
import '../ecs/entity.dart';
import '../ecs/world.dart';

/// Sets an entity's `Velocity` directly — the most common thing a
/// movement-driving behavior needs, so it ships with the engine rather
/// than making every game redefine it.
class SetVelocityAction implements Action {
  final EntityId entity;
  final double vx;
  final double vy;

  SetVelocityAction(this.entity, this.vx, this.vy);

  @override
  void apply(World world) {
    world.storeOf<Velocity>().set(entity, Velocity(vx, vy));
  }
}
