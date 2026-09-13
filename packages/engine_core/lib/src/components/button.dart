/// Marks an entity as a tappable UI button — the ECS equivalent of a
/// Flutter `ElevatedButton`, for a menu authored as ordinary world
/// entities (a `Sprite` + `Collider` + `Button`) instead of Flutter
/// widgets. `actionId` names what the button does; a `Scene`'s
/// `handleTap` reads it the same way `AIState.behaviorId` names a
/// `Behavior` — data referencing code registered ahead of time, not
/// code embedded in the entity itself. Hit-testing uses the entity's
/// `Collider` radius (see `hitTestButton`), so any button needs both.
class Button {
  String actionId;
  Button(this.actionId);

  Map<String, dynamic> toJson() => {'actionId': actionId};

  factory Button.fromJson(Map<String, dynamic> json) =>
      Button(json['actionId'] as String);
}
