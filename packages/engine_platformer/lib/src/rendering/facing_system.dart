import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

/// Flips `Sprite.scaleX` to face the direction of horizontal movement —
/// the standard "character faces the way it's walking" platformer
/// behavior. Only flips while moving faster than [threshold]; holds the
/// last facing while idle rather than snapping back to a default, since
/// there's no "default" facing that makes sense for every character.
class FacingSystem implements System {
  final double threshold;

  FacingSystem({this.threshold = 1});

  @override
  String get name => 'facing';

  @override
  void update(World world, double dt) {
    final velocities = world.storeOf<Velocity>();
    final sprites = world.storeOf<Sprite>();

    for (var i = 0; i < sprites.length; i++) {
      final entity = sprites.entityAt(i);
      final sprite = sprites.denseAt(i);
      final vel = velocities.get(entity);
      if (vel == null) continue;

      if (vel.x > threshold) {
        sprite.scaleX = sprite.scaleX.abs();
      } else if (vel.x < -threshold) {
        sprite.scaleX = -sprite.scaleX.abs();
      }
    }
  }
}
