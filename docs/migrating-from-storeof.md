# Migrating from `World.storeOf`

`World.storeOf<T>()` is deprecated and will be removed in a later release
(after at least one tagged release, because projects pin `ref: main`).
Everything it did has a clearer name.

| Before | After | Notes |
|---|---|---|
| `world.storeOf<T>()` | `world.componentsOf<T>()` | Same collection, same object. Rename only. |
| `world.storeOf<T>().get(id)` | `world.getComponent<T>(id)` | Returns `null` when absent, also for dead entities. |
| `world.storeOf<T>().set(id, v)` | `world.setComponent(id, v)` | **Throws** on a dead or never-spawned entity, which `.set` silently accepted. |
| `world.storeOf<T>().has(id)` | `world.hasComponent<T>(id)` | |
| `world.storeOf<T>().remove(id)` | `world.removeComponent<T>(id)` | No-op when absent. |
| a loop over `entityAt(i)` / `denseAt(i)` of the store | `world.query<T>()` / `query2` / `query3` | Joins several components without nested lookups. |

## Safe order of migration

1. Rename every `storeOf<T>()` to `componentsOf<T>()`. Behavior is identical, so
   this is a pure search-and-replace and can land on its own.
2. Move call sites to `getComponent` / `setComponent` where that reads better.
   Do this one directory at a time and run its tests: `setComponent` rejecting
   dead entities can surface a latent bug (writing to an entity destroyed earlier
   in the same step). The fix is usually to use `world.commands` for deferred changes.
3. Hot loops may keep `componentsOf<T>()` and call `denseAt(i)` / `entityAt(i)`
   directly; that is the fastest path and is not deprecated.

`ComponentRegistry.storeOf` (`world.components.storeOf<T>()`) is unchanged.
