import 'dart:convert';

import 'package:zarvan_flutter/zarvan_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../level/level_data.dart';
import '../progress/hero_progress.dart';
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
    this.splash = const SplashConfig(),
    this.viewportFit = ViewportFit.contain,
  });

  @override
  final GameConfig config;
  final LevelData level;
  final WaveCombatConfig combat;

  /// Splash artwork; the default shows the ZARVAN logo.
  @override
  final SplashConfig splash;

  /// How the fixed-aspect world meets the screen. [ViewportFit.contain]
  /// (default) keeps all of it and leaves black bars on screens of another
  /// shape; [ViewportFit.cover] fills the whole screen and crops the overflow,
  /// so keep HUD elements away from the cropped edges.
  final ViewportFit viewportFit;

  /// Loads the engine config (`assets/game_config.json` by default) and the
  /// level JSON, then builds the game.
  static Future<WaveCombatGame> load({
    required String levelAsset,
    required WaveCombatConfig combat,
    String configAsset = 'assets/game_config.json',
    SplashConfig splash = const SplashConfig(),
    ViewportFit viewportFit = ViewportFit.contain,
  }) async => WaveCombatGame(
    config: await GameConfig.loadFromAsset(configAsset),
    level: LevelData.fromJson(
      jsonDecode(await rootBundle.loadString(levelAsset))
          as Map<String, dynamic>,
    ),
    combat: combat,
    splash: splash,
    viewportFit: viewportFit,
  );

  @override
  ViewportConfig get viewportConfig => ViewportConfig(
    targetAspectRatio: config.worldWidth / config.worldHeight,
    fit: viewportFit,
    avoidSystemUi: false,
    centerViewport: true,
    fitWorld: true,
  );

  @override
  Scene createInitialScene() =>
      WaveCombatScene(level: level, config: combat, progress: progress);

  /// Coins and upgrades, kept across retries of this game session.
  final HeroProgress progress = HeroProgress();
}
