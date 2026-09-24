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

  /// See `EngineView.showPerformanceOverlay`'s doc comment — Flutter's
  /// own UI-thread/raster-thread bar graphs. Off by default, same
  /// reasoning as [showColliderDebug]: a real per-frame cost of its
  /// own, so a shipped `game_config.json` typically leaves this off and
  /// only flips it on locally while chasing a specific perf report.
  final bool showPerformanceOverlay;

  /// See `EngineView.showAutoTileBitmask`'s doc comment — the debug
  /// overlay showing each auto-tiled cell's computed bitmask. Off by
  /// default, same reasoning as [showColliderDebug]. Composes with
  /// `Scene.showAutoTileBitmask` via OR in `GameRunner` — set this
  /// globally for a level-authoring build, or leave it off here and
  /// flip it per-scene instead.
  final bool showAutoTileBitmask;

  /// `false` (default — the system status bar/navigation bar stay
  /// visible, unchanged from before this existed). `true` hides them
  /// (`SystemUiMode.immersiveSticky` on Android/iOS — a swipe from the
  /// screen edge still temporarily reveals them, rather than locking
  /// the user out of system gestures entirely) so the game draws under
  /// the whole screen instead of the OS status bar visibly overlapping
  /// the game's own UI — e.g. `showFpsOverlay`'s top-left readout or a
  /// screen-space HUD sitting right underneath the clock/battery icons
  /// on a real device. No effect on desktop/web, which don't have an
  /// overlaid system status bar to hide in the first place.
  final bool fullscreen;

  final bool pauseOnBackground;
  final OnScreenControlsMode onScreenControls;

  /// See `EngineView.ambientBrightness`'s doc comment — `1.0` (default)
  /// disables the lighting pass entirely; a lower value darkens the
  /// scene, revealed again through each `Light2D` entity.
  final double ambientBrightness;

  /// See `EngineView.maxFps`'s doc comment — `null` (default) runs at
  /// however fast the platform's raw display callback fires; set `60`
  /// for a stable, platform-independent rate instead of whatever a
  /// given device's actual refresh rate happens to be.
  final int? maxFps;

  /// See `EngineView.singlePassLighting`'s doc comment — `false` (default)
  /// uses the legacy multi-pass lighting (saveLayer + dark rect + N light
  /// holes). `true` enables the single-pass shader approach
  /// (`ambient_lighting.frag`) which computes the combined darkness mask
  /// for all lights in one fragment shader invocation.
  final bool singlePassLighting;

  /// Atlas id under which `GameRunner` auto-registers a single packed
  /// sprite sheet (see [packedAtlasImage]/[packedAtlasManifest]) into
  /// *every* `Scene`'s `AtlasRegistry`, produced ahead of time by
  /// `game_agent pack-assets` from a directory of individual level
  /// image assets — fewer atlas image decodes and fewer texture binds
  /// per frame than one atlas per source image. `null` (default, all
  /// three fields) means no packed atlas is registered at all, the
  /// original per-scene `loadAssets` behavior. All three fields are
  /// meaningless unless set together; a `Scene` that already registers
  /// something under this same id in its own `loadAssets` wins (the
  /// auto-registration skips an id `AtlasRegistry.has` already, so an
  /// individual scene can still opt out or override). Whether this
  /// auto-registration actually runs is additionally gated by the
  /// `USE_PACKED_ATLAS` compile-time flag (see `runGame`'s doc
  /// comment) — set here so it's still data, not code, but overridable
  /// per build without editing this file (e.g. `--dart-define
  /// USE_PACKED_ATLAS=false` while iterating on art, where reloading
  /// individual images per scene is more convenient than re-running
  /// the packer on every change).
  final String? packedAtlasId;

  /// Bundled asset path to the packed image `game_agent pack-assets`
  /// wrote (its `--output-image`, e.g. `assets/packed/atlas.png`) —
  /// must be declared under `flutter.assets` in `pubspec.yaml` like any
  /// other bundled asset. See [packedAtlasId].
  final String? packedAtlasImage;

  /// Bundled asset path to the packed manifest `game_agent pack-assets`
  /// wrote (its `--output-manifest`) — the same
  /// `{"regions": {"name": {"x","y","w","h"}}}` shape
  /// `SpriteAtlas.fromManifest` already reads for a hand-authored atlas.
  /// See [packedAtlasId].
  final String? packedAtlasManifest;

  const GameConfig({
    this.title = 'Game',
    this.orientation = GameOrientation.auto,
    required this.worldWidth,
    required this.worldHeight,
    this.backgroundColor = const Color(0xFF000000),
    this.showFpsOverlay = false,
    this.showColliderDebug = false,
    this.showPerformanceOverlay = false,
    this.showAutoTileBitmask = false,
    this.fullscreen = false,
    this.pauseOnBackground = true,
    this.onScreenControls = OnScreenControlsMode.auto,
    this.ambientBrightness = 1.0,
    this.maxFps,
    this.singlePassLighting = false,
    this.packedAtlasId,
    this.packedAtlasImage,
    this.packedAtlasManifest,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'orientation': orientation.name,
        'worldWidth': worldWidth,
        'worldHeight': worldHeight,
        'backgroundColor': backgroundColor.toARGB32(),
        'showFpsOverlay': showFpsOverlay,
        'showColliderDebug': showColliderDebug,
        'showPerformanceOverlay': showPerformanceOverlay,
        'showAutoTileBitmask': showAutoTileBitmask,
        'fullscreen': fullscreen,
        'pauseOnBackground': pauseOnBackground,
        'onScreenControls': onScreenControls.name,
        'ambientBrightness': ambientBrightness,
        'singlePassLighting': singlePassLighting,
        if (maxFps != null) 'maxFps': maxFps,
        if (packedAtlasId != null) 'packedAtlasId': packedAtlasId,
        if (packedAtlasImage != null) 'packedAtlasImage': packedAtlasImage,
        if (packedAtlasManifest != null) 'packedAtlasManifest': packedAtlasManifest,
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
        showPerformanceOverlay: json['showPerformanceOverlay'] as bool? ?? false,
        showAutoTileBitmask: json['showAutoTileBitmask'] as bool? ?? false,
        fullscreen: json['fullscreen'] as bool? ?? false,
        pauseOnBackground: json['pauseOnBackground'] as bool? ?? true,
        onScreenControls: OnScreenControlsMode.values.firstWhere(
          (m) => m.name == json['onScreenControls'],
          orElse: () => OnScreenControlsMode.auto,
        ),
        ambientBrightness: (json['ambientBrightness'] as num?)?.toDouble() ?? 1.0,
        maxFps: (json['maxFps'] as num?)?.toInt(),
        singlePassLighting: json['singlePassLighting'] as bool? ?? false,
        packedAtlasId: json['packedAtlasId'] as String?,
        packedAtlasImage: json['packedAtlasImage'] as String?,
        packedAtlasManifest: json['packedAtlasManifest'] as String?,
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

  /// Applies [fullscreen] — `SystemUiMode.immersiveSticky` (status/
  /// navigation bars hidden, revealed temporarily by a swipe from the
  /// screen edge) when `true`, `SystemUiMode.edgeToEdge` (the platform
  /// default — bars visible) when `false`.
  Future<void> applyFullscreen() {
    return SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }
}
