/// Marks an entity as agent-controlled and names which registered
/// `Behavior` drives it. `memory` is a free-form, JSON-serializable
/// blackboard a behavior can use to carry state between ticks (a patrol
/// waypoint index, a cooldown timer, etc.) without needing its own
/// component type.
class AIState {
  String behaviorId;
  Map<String, dynamic> memory;

  AIState(this.behaviorId, {Map<String, dynamic>? memory})
      : memory = memory ?? <String, dynamic>{};

  Map<String, dynamic> toJson() => {
        'behaviorId': behaviorId,
        'memory': memory,
      };

  factory AIState.fromJson(Map<String, dynamic> json) => AIState(
        json['behaviorId'] as String,
        memory: (json['memory'] as Map?)?.cast<String, dynamic>(),
      );
}
