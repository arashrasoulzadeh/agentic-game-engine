/// Idle / incremental-game layer on top of `engine_core` and `engine_flutter`.
///
/// The genre-general pieces (big numbers, offline progress, cost curves, the modifier stack) live in
/// `engine_core` because they are not specific to idle games; this package holds the genre's components,
/// systems and widgets. Plan and status: `TODO_IDLE.md` at the repository root.
library;

export 'src/active_play.dart';
export 'src/components.dart';
export 'src/economy.dart';
export 'src/progression.dart';
export 'src/register_components.dart';
export 'src/ui/idle_controller.dart';
export 'src/ui/idle_widgets.dart';
