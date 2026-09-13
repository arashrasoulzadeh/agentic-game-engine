import 'components/trigger_zone.dart';
import 'entity.dart';
import 'systems/collision_system.dart';
import 'world.dart';

/// Fired once per touch between [other] and a `TriggerZone`-tagged
/// entity ([zone]) — see `installTriggerZones`. [triggerId]/[data] are
/// copied straight from that `TriggerZone` at the moment of the touch.
class TriggerEvent {
  final String triggerId;
  final EntityId zone;
  final EntityId other;
  final Map<String, dynamic> data;

  TriggerEvent(this.triggerId, this.zone, this.other, this.data);
}

/// Wires up every `TriggerZone` in [world]: whenever something collides
/// with one, emits `TriggerEvent`. Call once (e.g. from `Scene.populate`,
/// after `CollisionSystem` is registered) — same "subscribe once at
/// setup" shape as `onCollisionInvolving`/`onCollisionWithAny`, not a
/// per-tick `System`, since all this does is translate `CollisionEvent`
/// into a more specific event for zones.
///
/// A level author only ever has to attach a `TriggerZone` component and
/// give it an id — no custom Dart per zone the way a bespoke
/// `onCollisionInvolving` handler would otherwise need, the same
/// "menu is data, not code" shift `ButtonMenuScene` made for menus.
void installTriggerZones(World world) {
  world.events.on<CollisionEvent>((event) {
    final zones = world.storeOf<TriggerZone>();
    final zoneA = zones.get(event.a);
    if (zoneA != null) {
      world.events.emit(TriggerEvent(zoneA.triggerId, event.a, event.b, zoneA.data));
    }
    final zoneB = zones.get(event.b);
    if (zoneB != null) {
      world.events.emit(TriggerEvent(zoneB.triggerId, event.b, event.a, zoneB.data));
    }
  });
}
