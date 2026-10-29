/// Platformer-dependent idle-combat helpers: auto-fight systems, fighter
/// spawning, sprite-sheet loading and level/wave data. Kept apart from the
/// Flutter-free idle rules so only games that want them pull in
/// `engine_platformer`.
library;

export 'combat/auto_combat_system.dart';
export 'combat/combat_components.dart';
export 'combat/fighter_anims.dart';
export 'combat/spawn_fighter.dart';
export 'fighters/fighter_meta.dart';
export 'fighters/pivots.dart';
export 'fx/fx.dart';
export 'hud/scene_hud.dart';
export 'level/level_data.dart';
export 'level/parallax.dart';
export 'level/wave_progress.dart';
export 'sheet_atlas.dart';
