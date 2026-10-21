# engine_idle

Idle / incremental games on top of [engine_core](../engine_core/README.md) and
[engine_flutter](../engine_flutter/README.md): generators, upgrades, prestige, achievements and the widgets that
show them. The genre-general maths and persistence (big numbers, offline progress, save versioning) live in
`engine_core`; this package is the genre-specific assembly, the way `engine_strategy` is for strategy games.

**Status: scaffold.** The package exists and is wired into CI; the features are being built in the order given in
[TODO_IDLE.md](../../TODO_IDLE.md).

```dart
final world = World(width: 800, height: 600);
registerCoreComponents(world);
registerIdleComponents(world);
```
