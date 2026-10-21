/// The idle-game rules without any Flutter dependency, so command-line tools (the balance simulator) and
/// server code can use them. `package:engine_idle/engine_idle.dart` re-exports all of this plus the widgets.
library;

export 'src/active_play.dart';
export 'src/components.dart';
export 'src/definition.dart';
export 'src/economy.dart';
export 'src/progression.dart';
export 'src/register_components.dart';
export 'src/simulator.dart';
