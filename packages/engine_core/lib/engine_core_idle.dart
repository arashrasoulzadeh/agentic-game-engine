/// The idle / incremental-game rules, free of Flutter: components, economy, progression, saving-independent
/// logic, golden events, the data-driven game definition and the balance simulator. Command-line tools
/// (`game_agent`), servers and tests import this; `package:engine_idle/engine_idle.dart` re-exports it and
/// adds the widgets and the app-lifecycle session.
///
/// A separate entry point, not part of `engine_core.dart`, because these names (`Generator`, `Upgrade`,
/// `Achievement`, ...) belong to one genre and would crowd every other game's imports.
library;

export 'src/idle/active_play.dart';
export 'src/idle/advisor.dart';
export 'src/idle/analytics.dart';
export 'src/idle/auto_buyer.dart';
export 'src/idle/challenges.dart';
export 'src/idle/components.dart';
export 'src/idle/definition.dart';
export 'src/idle/definition_schema.dart';
export 'src/idle/economy.dart';
export 'src/idle/golden_events.dart';
export 'src/idle/progression.dart';
export 'src/idle/register_components.dart';
export 'src/idle/research.dart';
export 'src/idle/season_pass.dart';
export 'src/idle/simulator.dart';
export 'src/idle/time_warp.dart';
