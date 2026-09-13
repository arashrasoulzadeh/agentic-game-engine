import 'package:engine_core/engine_core.dart';

import 'components/inventory.dart';

/// Emitted by [collectItem] whenever it actually adds to an
/// `Inventory` — a no-op call (no `Inventory` on [holder]) never fires
/// this, the same "only fires on a real change" guarantee `DeathEvent`
/// gives.
class ItemCollectedEvent {
  final EntityId holder;
  final String itemId;
  final int amount;
  ItemCollectedEvent(this.holder, this.itemId, this.amount);
}

/// Adds [amount] of [itemId] to [holder]'s `Inventory` and emits
/// [ItemCollectedEvent]. A no-op if [holder] has no `Inventory`
/// component — safe to call from a collision handler without checking
/// first, the same pattern `damageEntity` uses for `Health`.
void collectItem(World world, EntityId holder, String itemId, {int amount = 1}) {
  final inventory = world.storeOf<Inventory>().get(holder);
  if (inventory == null) return;

  inventory.items[itemId] = inventory.count(itemId) + amount;
  world.events.emit(ItemCollectedEvent(holder, itemId, amount));
}

/// Wires up "touching any of [pickups] collects [itemId]" in one call
/// — the common case (coins, keys, power-ups) via
/// `World.onCollisionWithAny` under the hood. [destroyOnCollect]
/// (default `true`) removes the pickup entity once collected; pass
/// `false` for something reusable (e.g. a lever that can be triggered
/// more than once). For anything more specific (different items per
/// pickup, conditional collection), call [collectItem] directly from
/// your own collision listener instead.
void dealPickupOnTouch(
  World world,
  Set<EntityId> pickups,
  String itemId, {
  int amount = 1,
  bool destroyOnCollect = true,
}) {
  world.onCollisionWithAny(pickups, (pickup, other) {
    collectItem(world, other, itemId, amount: amount);
    if (destroyOnCollect) world.destroy(pickup);
  });
}
