import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;

import 'health_hud_link.dart';

/// Spawns a `HudBar` linked to [source]'s `Health` via `HealthHudLink`,
/// kept in sync every tick by `HealthHudSystem` — the one-call version
/// of "put a health bar on this entity", matching the shape of
/// `spawnPlayer`/`spawnEnemy`: a game still owns position/size/colors,
/// this just wires up the mechanical part. [screenSpace] defaults
/// `true` (a HUD bar pinned to the viewport, [x]/[y] in pixels); pass
/// `false` for a world-space bar meant to float over [source] itself
/// (an enemy's health bar) — [x]/[y] are then world units, and a game
/// still has to update the returned entity's `Position` each tick to
/// follow [source] around (see `HudBar.screenSpace`'s doc comment).
/// Returns the new `HudBar` entity.
EntityId spawnHealthHudBar(
  World world, {
  required EntityId source,
  required double x,
  required double y,
  double width = 100,
  double height = 12,
  int fillColorArgb = 0xFFE0304C,
  int backgroundColorArgb = 0x80000000,
  bool screenSpace = true,
  int zIndex = 0,
}) {
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(x, y));
  world.storeOf<HudBar>().set(
        id,
        HudBar(
          value: 0,
          maxValue: 0,
          width: width,
          height: height,
          fillColorArgb: fillColorArgb,
          backgroundColorArgb: backgroundColorArgb,
          screenSpace: screenSpace,
          zIndex: zIndex,
        ),
      );
  world.storeOf<HealthHudLink>().set(id, HealthHudLink(source));
  return id;
}
