import 'dart:convert';

import 'package:flutter/services.dart';

/// Screen orientation lock for a game. `auto` leaves the device's default
/// (usually all orientations) in place — most 2D platformers want
/// `landscape`, most puzzle/vertical games want `portrait`.
enum GameOrientation { portrait, landscape, auto }

/// Declarative, JSON-serializable game settings — the first piece of the
/// "content is data, not code" principle: an agent (or a human) can
/// change orientation, world size, or the title by editing a file, no
/// Dart required. Loaded once at startup by `runGame`/`GameRunner`.
class GameConfig {
  final String title;
  final GameOrientation orientation;
  final double worldWidth;
  final double worldHeight;
  final Color backgroundColor;
  final bool showFpsOverlay;
  final bool pauseOnBackground;

  const GameConfig({
    this.title = 'Game',
    this.orientation = GameOrientation.auto,
    required this.worldWidth,
    required this.worldHeight,
    this.backgroundColor = const Color(0xFF000000),
    this.showFpsOverlay = false,
    this.pauseOnBackground = true,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'orientation': orientation.name,
        'worldWidth': worldWidth,
        'worldHeight': worldHeight,
        'backgroundColor': backgroundColor.toARGB32(),
        'showFpsOverlay': showFpsOverlay,
        'pauseOnBackground': pauseOnBackground,
      };

  factory GameConfig.fromJson(Map<String, dynamic> json) => GameConfig(
        title: json['title'] as String? ?? 'Game',
        orientation: GameOrientation.values.firstWhere(
          (o) => o.name == json['orientation'],
          orElse: () => GameOrientation.auto,
        ),
        worldWidth: (json['worldWidth'] as num).toDouble(),
        worldHeight: (json['worldHeight'] as num).toDouble(),
        backgroundColor: json['backgroundColor'] != null
            ? Color(json['backgroundColor'] as int)
            : const Color(0xFF000000),
        showFpsOverlay: json['showFpsOverlay'] as bool? ?? false,
        pauseOnBackground: json['pauseOnBackground'] as bool? ?? true,
      );

  /// Loads a `GameConfig` from a bundled JSON asset, e.g.
  /// `assets/game_config.json` declared in the game's `pubspec.yaml`.
  static Future<GameConfig> loadFromAsset(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return GameConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> applyOrientation() {
    switch (orientation) {
      case GameOrientation.portrait:
        return SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      case GameOrientation.landscape:
        return SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      case GameOrientation.auto:
        return SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }
}
