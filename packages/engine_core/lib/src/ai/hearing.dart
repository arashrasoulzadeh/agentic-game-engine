import 'dart:math';

import '../ecs/world_view.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import '../physics/position.dart';
import '../ai/ai_state.dart';

/// Represents a sound that propagates through the world and can be heard
/// by entities with a `HearingComponent`. Emitted via `world.events.emit(...)`.
///
/// [loudness] determines how far the sound travels (in world pixels).
/// A sound with loudness 200 can be heard up to 200px away by an
/// entity with `HearingComponent.range >= 200`.
class SoundEvent {
  final double x;
  final double y;
  final double loudness;

  /// Optional tag to categorize the sound (e.g., 'footstep', 'gunshot', 'explosion').
  /// Can be used by `InvestigateBehavior` or custom logic to filter.
  final String? tag;

  /// Optional data payload for custom sound metadata.
  final Map<String, dynamic>? data;

  const SoundEvent({
    required this.x,
    required this.y,
    required this.loudness,
    this.tag,
    this.data,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'loudness': loudness,
        if (tag != null) 'tag': tag,
        if (data != null) 'data': data,
      };

  factory SoundEvent.fromJson(Map<String, dynamic> json) => SoundEvent(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        loudness: (json['loudness'] as num).toDouble(),
        tag: json['tag'] as String?,
        data: (json['data'] as Map?)?.cast<String, dynamic>(),
      );
}

/// Component that gives an entity the ability to "hear" sounds.
/// When a `SoundEvent` occurs within range and with line of sight,
/// the entity's `AIState.memory['lastHeardSound']` is updated.
class HearingComponent {
  /// Maximum distance (in world pixels) this entity can hear.
  /// A sound with loudness L is audible if `distance <= min(range, L)`.
  final double range;

  HearingComponent({required this.range});

  Map<String, dynamic> toJson() => {'range': range};

  factory HearingComponent.fromJson(Map<String, dynamic> json) =>
      HearingComponent(range: (json['range'] as num).toDouble());
}

/// System that processes `SoundEvent`s and updates the `AIState.memory`
/// of entities with `HearingComponent` that can hear them.
///
/// Subscribes to `SoundEvent` on the `EventBus` and, for each sound,
/// checks all entities with `HearingComponent` + `Position` to see if:
/// 1. The sound is within the entity's hearing range AND within the sound's loudness.
/// 2. The sound is not fully tile-occluded (uses `raycastTileMap` / `hasLineOfSight`).
///
/// On a heard sound, writes `memory['lastHeardSound'] = {'x': ..., 'y': ..., 'loudness': ..., 'tag': ..., 'data': ...}`
/// to the entity's `AIState`, overwriting any previous heard sound.
class HearingSystem implements System {
  @override
  String get name => 'hearing';

  @override
  void update(World world, double dt) {
    // We process sounds by subscribing to events during update.
    // This is a bit unusual - typically systems are polled each tick,
    // but since SoundEvents are emitted asynchronously via the EventBus,
    // we need to subscribe once. The subscription persists across ticks.
    // We use a flag on the world to ensure we only subscribe once.
    if (!world.hasHearingSubscription) {
      world.hasHearingSubscription = true;
      world.events.on<SoundEvent>((SoundEvent sound) {
        _processSound(world, sound);
      });
    }
  }

  void _processSound(World world, SoundEvent sound) {
    final positions = world.storeOf<Position>();
    final hearings = world.storeOf<HearingComponent>();
    final aiStates = world.storeOf<AIState>();

    if (hearings.length == 0) return;

    // Quick spatial filter: only check entities within sound.loudness of the sound origin
    // We can use WorldView's spatial queries if available, or just iterate.
    // For now, iterate all hearing entities - O(N) is fine for typical entity counts.
    final view = WorldView(world);

    for (var i = 0; i < hearings.length; i++) {
      final entity = hearings.entityAt(i);
      final hearing = hearings.denseAt(i);

      final pos = positions.get(entity);
      if (pos == null) continue;

      // Check distance: must be within BOTH hearing.range AND sound.loudness
      final dx = pos.x - sound.x;
      final dy = pos.y - sound.y;
      final distanceSq = dx * dx + dy * dy;
      final maxDistance = hearing.range < sound.loudness ? hearing.range : sound.loudness;
      if (distanceSq > maxDistance * maxDistance) continue;

      // Check line of sight (tile occlusion only, not entity occlusion)
      // Offset the ray start slightly toward the sound to avoid hitting the
      // tile the entity is standing on (common when entity is on the ground).
      const offset = 2.0;
      final dirX = sound.x - pos.x;
      final dirY = sound.y - pos.y;
      final dist = sqrt(dirX * dirX + dirY * dirY);
      final fromX = pos.x + (dist > 0 ? dirX / dist * offset : 0);
      final fromY = pos.y + (dist > 0 ? dirY / dist * offset : 0);

      if (!view.hasLineOfSight(fromX, fromY, sound.x, sound.y)) continue;

      // Sound is heard! Update AIState.memory
      final aiState = aiStates.get(entity);
      if (aiState != null) {
        aiState.memory['lastHeardSound'] = {
          'x': sound.x,
          'y': sound.y,
          'loudness': sound.loudness,
          if (sound.tag != null) 'tag': sound.tag,
          if (sound.data != null) 'data': sound.data,
        };
      }
    }
  }
}

/// Extension to store the hearing subscription flag on World.
/// This is a workaround since we can't add fields to World directly.
/// In a real implementation, we'd add a field to World or use a separate
/// registry. For now, we use a map keyed by World identity.
final Map<int, bool> _worldHearingSubscriptions = {};

extension WorldHearingExtension on World {
  bool get hasHearingSubscription {
    return _worldHearingSubscriptions[identityHashCode(this)] ?? false;
  }

  set hasHearingSubscription(bool value) {
    _worldHearingSubscriptions[identityHashCode(this)] = value;
  }
}