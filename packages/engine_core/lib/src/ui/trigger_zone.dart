/// Marks an entity as a trigger zone: something a game reacts to on
/// touch without it ever blocking movement or physically resolving,
/// unlike a solid `Collider`. The generic counterpart to `RoomExit`
/// (which is a trigger baked specifically for room transitions) — use
/// this for anything else a level wants to happen on overlap: a
/// checkpoint activation, a cutscene starter, a dialogue prompt, any
/// custom game-specific event. [triggerId] is a name your own event
/// handler matches on (see `installTriggerZones`); [data] is a
/// free-form JSON-serializable payload (which dialogue line, which
/// checkpoint id, ...) — the same "reference registered code by id,
/// carry a blackboard of free-form data" pattern as `AIState`.
///
/// Needs a `Position` + `Collider` on the same entity, like `Button`.
/// Deliberately **don't** also give it a `Velocity` — `CollisionSystem`
/// only swaps velocities between a colliding pair when *both* sides
/// have one (see its own doc comment), so a `Velocity`-less trigger
/// zone is never physically affected by (or elastically bumps) whatever
/// touches it; it only ever fires `TriggerEvent`.
class TriggerZone {
  String triggerId;
  Map<String, dynamic> data;

  TriggerZone(this.triggerId, {Map<String, dynamic>? data}) : data = data ?? <String, dynamic>{};

  Map<String, dynamic> toJson() => {
        'triggerId': triggerId,
        'data': data,
      };

  factory TriggerZone.fromJson(Map<String, dynamic> json) => TriggerZone(
        json['triggerId'] as String,
        data: (json['data'] as Map?)?.cast<String, dynamic>(),
      );
}
