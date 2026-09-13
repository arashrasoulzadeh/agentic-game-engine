import 'dart:convert';

import 'package:flutter/services.dart';

/// Screen orientation lock for a game. `auto` leaves the device's default
/// (usually all orientations) in place — most 2D platformers want
/// `landscape`, most puzzle/vertical games want `portrait`.
enum GameOrientation { portrait, landscape, auto }

/// Whether to overlay touch controls (`OnScreenControls`). `auto` shows
/// them on Android/iOS and hides them elsewhere (desktop/web assume a
/// keyboard) — override with `on`/`off` for a game that wants touch
/// controls everywhere (e.g. testing them in a browser) or nowhere
/// (e.g. a game with no player-controlled movement at all).
enum OnScreenControlsMode { auto, on, off }

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

  /// See `EngineView.showColliderDebug`'s doc comment — a stroked
  /// outline per `Collider`/solid-or-one-way-or-slope tile, on top of
  /// everything else. Off by default; a game typically only flips this
  /// on for local development (e.g. via a debug build flag), not in a
  /// shipped `game_config.json`.
  final bool showColliderDebug;
  final bool pauseOnBackground;
  final OnScreenControlsMode onScreenControls;

  /// See `EngineView.ambientBrightness`'s doc comment — `1.0` (default)
  /// disables the lighting pass entirely; a lower value darkens the
  /// scene, revealed again through each `Light2D` entity.
  final double ambientBrightness;

  const GameConfig({
    this.title = 'Game',
    this.orientation = GameOrientation.auto,
    required this.worldWidth,
    required this.worldHeight,
    this.backgroundColor = const Color(0xFF000000),
    this.showFpsOverlay = false,
    this.showColliderDebug = false,
    this.pauseOnBackground = true,
    this.onScreenControls = OnScreenControlsMode.auto,
    this.ambientBrightness = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'orientation': orientation.name,
        'worldWidth': worldWidth,
        'worldHeight': worldHeight,
        'backgroundColor': backgroundColor.toARGB32(),
        'showFpsOverlay': showFpsOverlay,
        'showColliderDebug': showColliderDebug,
        'pauseOnBackground': pauseOnBackground,
        'onScreenControls': onScreenControls.name,
        'ambientBrightness': ambientBrightness,
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
        showColliderDebug: json['showColliderDebug'] as bool? ?? false,
        pauseOnBackground: json['pauseOnBackground'] as bool? ?? true,
        onScreenControls: OnScreenControlsMode.values.firstWhere(
          (m) => m.name == json['onScreenControls'],
          orElse: () => OnScreenControlsMode.auto,
        ),
        ambientBrightness: (json['ambientBrightness'] as num?)?.toDouble() ?? 1.0,
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
