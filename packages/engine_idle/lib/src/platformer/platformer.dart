/// Platformer-dependent idle-combat helpers: auto-fight systems, fighter
/// spawning, sprite-sheet loading and level/wave data. Kept apart from the
/// Flutter-free idle rules so only games that want them pull in
/// `engine_platformer`.
library;

export 'combat/auto_combat_system.dart';
export 'combat/combat_components.dart';
export 'combat/fighter_death_system.dart';
export 'combat/spawn_fighter.dart';
export 'fighters/fighter_meta.dart';
export 'fx/combat_fx.dart';
export 'hud/dialogue_caption.dart';
export 'hud/sprite_health_bar.dart';
export 'hud/wave_path.dart';
export 'hud/wave_ui_art.dart';
export 'hud/hud_layout.dart';
export 'hud/scene_hud.dart';
export 'level/level_data.dart';
export 'level/wave_progress.dart';
export 'scene/walk_phase.dart';
export 'scene/wave_combat_game.dart';
export 'scene/wave_combat_scene.dart';
