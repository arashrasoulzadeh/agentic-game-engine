import 'dart:convert';

import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../level/level_data.dart';
import 'wave_combat_scene.dart';

/// A whole wave-combat game: the engine's `Game` around a [WaveCombatScene].
///
/// `void main() async { WidgetsFlutterBinding.ensureInitialized(); runGame(await
/// WaveCombatGame.load(levelAsset: ..., combat: ...)); }` is the entire Dart a
/// game needs; the world is letterboxed and scaled to the window by the
/// engine (`ViewportConfig.fittingWorld`).
class WaveCombatGame extends Game {
  WaveCombatGame({
    required this.config,
    required this.level,
    required this.combat,
  });

  @override
  final GameConfig config;
  final LevelData level;
  final WaveCombatConfig combat;

  /// Loads the engine config (`assets/game_config.json` by default) and the
  /// level JSON, then builds the game.
  static Future<WaveCombatGame> load({
    required String levelAsset,
    required WaveCombatConfig combat,
    String configAsset = 'assets/game_config.json',
  }) async => WaveCombatGame(
    config: await GameConfig.loadFromAsset(configAsset),
    level: LevelData.fromJson(
      jsonDecode(await rootBundle.loadString(levelAsset))
          as Map<String, dynamic>,
    ),
    combat: combat,
  );

  @override
  ViewportConfig get viewportConfig =>
      ViewportConfig.fittingWorld(config.worldWidth, config.worldHeight);

  @override
  Scene createInitialScene() => WaveCombatScene(level: level, config: combat);
}
