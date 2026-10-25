/// Idle / incremental-game layer on top of `engine_core` and `engine_flutter`.
///
/// The genre-general pieces (big numbers, offline progress, cost curves, the modifier stack) live in
/// `engine_core` because they are not specific to idle games; this package holds the genre's components,
/// systems and widgets. Create-path status and polish backlog: Idle polish in `TODO.md`.
library;

export 'engine_idle_logic.dart';
export 'src/ui/idle_controller.dart';
export 'src/ui/idle_screens.dart';
export 'src/ui/idle_sfx.dart';
export 'src/ui/idle_widgets.dart';
export 'src/browser_save_store.dart';
export 'src/http_cloud_save_store.dart';
export 'src/session.dart';
export 'src/ui/idle_lifecycle.dart';
