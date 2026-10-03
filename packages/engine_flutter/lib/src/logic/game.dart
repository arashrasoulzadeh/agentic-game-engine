import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader, rootBundle;

import '../rendering/camera.dart';
import '../rendering/engine_view.dart';
import '../rendering/frame_stats.dart';
import 'game_config.dart';
import '../input/input.dart';
import '../input/on_screen_controls.dart';
import '../register_components.dart';
import 'scene.dart';
import 'scene_transition.dart';
import '../rendering/sprite_atlas.dart';

/// The top-level entry point a game implements. Extend this instead of
/// hand-wiring `World`/`Ticker`/`CustomPaint` yourself — `runGame` handles
/// orientation, asset loading, app-lifecycle pause/resume, scene
/// switching, and the render loop; you only define *what* the game is.
abstract class Game {
  GameConfig get config;

  /// The `Scene` (level/room) `GameRunner` loads first. A game with
  /// rooms/doors switches to further scenes at runtime via the
  /// `SceneController` handed to each `Scene.populate` call — see
  /// `Scene`'s doc comment.
  Scene createInitialScene();

  /// The `GameState` `GameRunner` creates once and hands to every
  /// `Scene.populate` call for this game's whole run — the one thing
  /// that survives a `loadScene` swap (see `Scene.populate`'s doc
  /// comment). Defaults to an empty state; override to seed starting
  /// values (e.g. `GameState({'coinsCollected': 0})`).
  GameState createInitialState() => GameState();

  /// Returns null (no keyboard input wired) by default — override to
  /// supply an `InputController` with custom key bindings. The same
  /// controller drives on-screen touch controls too (see
  /// `onScreenButtons`/`onScreenJoystickVertical`), so keyboard and
  /// touch input end up setting the exact same logical actions.
  InputController? createInputController() => null;

  /// Buttons shown by the default on-screen control overlay (see
  /// `GameConfig.onScreenControls`). Defaults to a single jump button —
  /// override for a game with more/different actions.
  List<OnScreenButtonSpec> onScreenButtons() =>
      const [OnScreenButtonSpec('jump', 'JUMP')];

  /// Whether the on-screen joystick also sets `"up"`/`"down"`. Off by
  /// default (the common platformer case, where vertical movement is
  /// gravity/jump, not joystick-driven) — override for a top-down or
  /// free-movement game.
  bool get onScreenJoystickVertical => false;

  /// Returns null (static camera) by default — override to make the
  /// camera follow a specific entity (typically the player) each frame.
  EntityId? cameraFollowEntity(World world) => null;

  /// `null` (default) — override to supply your own `FrameStats`
  /// instance, which `GameRunner` then keeps updated every frame (the
  /// same object passed to `EngineView.frameStats`, see its own doc
  /// comment) — read it yourself (e.g. log it periodically to a device
  /// you can `adb logcat`/console-attach to, when `EngineView.showFpsOverlay`'s
  /// on-screen readout isn't reachable) instead of relying only on the
  /// overlay text.
  FrameStats? get frameStats => null;

  /// Called when the app is backgrounded/inactive, if
  /// `config.pauseOnBackground` is true. Override for save-on-pause etc.
  void onPause() {}

  /// Called when the app returns to the foreground after a pause.
  void onResume() {}

  /// Shown while the initial scene's `populate`/`loadAssets` are
  /// running, before the first frame can render. A later
  /// `SceneController.loadScene` switch keeps rendering the outgoing
  /// scene (via Flutter's `FutureBuilder`, which retains the last
  /// resolved snapshot while a new future is in flight) rather than
  /// flashing back to this screen — override `Scene.loadAssets` to stay
  /// fast if a room switch should feel instant. Defaults to a centered
  /// spinner on the configured background color — override for a
  /// branded splash screen/logo instead.
  Widget buildLoadingScreen(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _LoadedGame {
  final World world;
  final AtlasRegistry atlasRegistry;
  final Camera camera;
  final InputController? inputController;
  final Scene scene;

  _LoadedGame(this.world, this.atlasRegistry, this.camera, this.inputController, this.scene);
}

/// Hosts a [Game]: applies orientation, loads assets, then renders via
/// `EngineView`. Use `runGame` unless you need to embed a game inside a
/// larger Flutter app (e.g. one tab of a bigger app) — in that case use
/// this widget directly instead of `runGame`'s full `MaterialApp` wrapper.
class GameRunner extends StatefulWidget {
  final Game game;

  const GameRunner({super.key, required this.game});

  @override
  State<GameRunner> createState() => _GameRunnerState();
}

class _GameRunnerState extends State<GameRunner> with WidgetsBindingObserver {
  final SceneController _sceneController = SceneController();
  late final GameState _gameState;
  late Future<_LoadedGame> _future;
  bool _paused = false;
  _LoadedGame? _overlay;

  /// Wraps the base scene's `EngineView` (not an overlay's, and not
  /// `OnScreenControls`) so [_captureScreenshot] can find its
  /// `RenderRepaintBoundary` and snapshot exactly the gameplay viewport
  /// — the same thing a player actually sees, not whatever UI happens
  /// to be layered on top.
  final GlobalKey _engineViewRepaintKey = GlobalKey();

  /// The `_future` a load error was already reported for -- `build`
  /// re-runs every frame while the loading screen's own spinner
  /// animates, and without this a single load failure would spam
  /// `FlutterError.reportError` once per frame for as long as it stays
  /// on screen instead of once, the moment it happens.
  Future<_LoadedGame>? _reportedErrorFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.game.config.applyOrientation();
    widget.game.config.applyFullscreen();
    _sceneController.attach(
      loadScene: _loadScene,
      pushOverlay: _pushOverlay,
      popOverlay: _popOverlay,
      loadSceneWithTransition: _loadSceneWithTransition,
      captureScreenshot: _captureScreenshot,
    );
    _gameState = widget.game.createInitialState();
    _future = _load(widget.game.createInitialScene());
  }

  /// The `SceneController` callback: rebuilds `_future` with [next], so
  /// `build`'s `FutureBuilder` shows the loading screen again while it
  /// resolves, then swaps in the new scene's `World`/camera/atlases.
  /// Also drops any active overlay — a full scene switch makes whatever
  /// was paused underneath it moot.
  void _loadScene(Scene next) {
    setState(() {
      _future = _load(next);
      _overlay = null;
    });
  }

  /// Loads [next] with an optional [transition] effect, in two phases
  /// sharing one `World` swap: [transition] plays once covering the
  /// current scene, [next] loads exactly like [_loadScene], then
  /// [transition] plays again revealing it. `EngineView` keeps ticking
  /// whichever `World` is live throughout (its own `Ticker` isn't gated
  /// by `setState`), which is what actually advances
  /// `SceneTransitionSystem`/the tween underneath each phase — this
  /// just awaits each phase's own real-time duration before moving on.
  Future<void> _loadSceneWithTransition(
    Scene next,
    SceneTransitionConfig? transition,
  ) async {
    if (transition == null) {
      _loadScene(next);
      return;
    }
    final outgoingWorld = (await _future).world;
    await _runTransitionPhase(outgoingWorld, transition, covering: true);
    _loadScene(next);
    final incomingWorld = (await _future).world;
    await _runTransitionPhase(incomingWorld, transition, covering: false);
  }

  /// Spawns a [SceneTransition] on [world] and waits out its real-time
  /// duration. [covering]: see [SceneTransition.covering].
  Future<void> _runTransitionPhase(
    World world,
    SceneTransitionConfig transition, {
    required bool covering,
  }) async {
    final entity = world.spawn();
    final sceneTransition = SceneTransition(config: transition, covering: covering);
    sceneTransition.start(world, cameraX: world.width / 2, cameraY: world.height / 2);
    world.storeOf<SceneTransition>().set(entity, sceneTransition);
    await Future.delayed(Duration(milliseconds: (transition.duration * 1000).round()));
    if (world.entities.isAlive(entity)) world.destroy(entity);
  }

  /// Loads [overlay] into its own small `World` (via the same `_load`
  /// every scene uses) without touching `_future` at all — the base
  /// scene's `World` just keeps existing, frozen (see `build`'s
  /// `paused: _paused || _overlay != null`), so popping the overlay
  /// resumes it exactly where it left off. This is the whole mechanism
  /// behind `SceneController.pushOverlay`'s "pause without losing
  /// state" contract.
  Future<void> _pushOverlay(Scene overlay) async {
    final loaded = await _load(overlay);
    if (!mounted) return;
    setState(() => _overlay = loaded);
  }

  void _popOverlay() {
    setState(() => _overlay = null);
  }

  /// Snapshots the base scene's `EngineView` (see
  /// [_engineViewRepaintKey]'s own doc comment) as PNG bytes —
  /// `SceneController.captureScreenshot`'s implementation, typically
  /// used right before `SaveGame.save(..., thumbnail: bytes)` for a
  /// save-slot preview. [pixelRatio] scales the capture relative to
  /// logical pixels; a thumbnail usually wants well under `1.0` to
  /// keep the saved bytes small. Returns `null` if `EngineView` hasn't
  /// painted a frame yet (its `RenderRepaintBoundary` isn't attached
  /// to the render tree until then) rather than throwing — a save
  /// taken too early just gets no thumbnail instead of crashing.
  Future<Uint8List?> _captureScreenshot({double pixelRatio = 1.0}) async {
    final renderObject = _engineViewRepaintKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    final image = await renderObject.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Lazily decoded once and reused for every scene load thereafter —
  /// `GameConfig.packedAtlasId`'s whole point is *fewer* atlas image
  /// decodes than one per source sprite, so re-decoding this same
  /// packed image from bytes on every `loadScene`/`pushOverlay` call
  /// would undermine that. `null` forever when packed-atlas config
  /// isn't set or `usePackedAtlas` is off, at no cost beyond the one
  /// null check in [_load].
  Future<SpriteAtlas>? _packedAtlasFuture;

  /// Flutter Web's font loading is asynchronous and the framework
  /// doesn't block the first frame on it — normally invisible, since a
  /// typical app's first real text appears after a user interaction,
  /// well after the font has finished loading in the background. This
  /// engine doesn't get that grace period: a `Scene.populate` can spawn
  /// `Text`/push a dialogue overlay on literally the very first frame,
  /// racing the bundled default font's `rootBundle.load`. Observed live
  /// on web/CanvasKit: `Text`'s `Position`/size/color were all correct
  /// and sprites rendered normally, but every glyph silently painted
  /// nothing — once a font family fails to resolve for a `Paragraph`,
  /// CanvasKit's `FontCollection` caches that failure for the rest of
  /// the session, so it doesn't self-correct once the bytes do arrive a
  /// few frames later. Awaited once, cached *on success only*, in
  /// [_load] (which already runs before any scene's content can need
  /// it) rather than per-call — caching a *failed* attempt here too
  /// used to permanently break every later scene load for the rest of
  /// the process (this field is `static`, so one transient asset-load
  /// failure poisoned it forever, with no way to recover): caught live
  /// via `packed_atlas_test.dart`'s test that deliberately fails an
  /// unrelated asset load by nulling out the whole `flutter/assets`
  /// channel, which left [_defaultFontFuture] permanently rejected and
  /// broke every `testWidgets` after it in the same process.
  static Future<void>? _defaultFontFuture;

  Future<void> _ensureDefaultFontLoaded() {
    final future = _defaultFontFuture ??= _loadDefaultFont();
    // Bounded, and forgets a failed/timed-out attempt instead of
    // caching the rejection forever (see [_defaultFontFuture]'s own doc
    // comment) — the next call retries from scratch rather than
    // replaying the same error. A missing/corrupt/slow-to-resolve
    // bundled font is also not worth treating as fatal to (or capable
    // of indefinitely stalling) the whole scene load: the engine
    // already tolerates a missing sprite atlas the same way (see
    // `DialogueBoxScene.loadAssets`) -- `Text` just falls back to
    // whatever typeface the platform resolves for an unset
    // `fontFamily`, which is exactly this engine's behavior before
    // this font ever existed. The timeout also matters for
    // `testWidgets` specifically: a `rootBundle.load` that never
    // replies (an asset channel mock with no handler for this path, or
    // one some other test in the same process left in a bad state)
    // would otherwise hang every later `GameRunner` test for the rest
    // of that 10-minute-timeout-bounded suite run instead of just this
    // one scene failing to get its font.
    return future.timeout(const Duration(seconds: 5), onTimeout: () {}).catchError(
      (Object error, StackTrace stackTrace) {
        _defaultFontFuture = null;
      },
    );
  }

  static Future<void> _loadDefaultFont() async {
    final loader = FontLoader('packages/engine_flutter/EngineDefault')
      ..addFont(
        rootBundle.load('packages/engine_flutter/assets/fonts/EngineDefault-Regular.ttf'),
      );
    await loader.load();
  }

  /// Builds a brand-new `World` for [scene] rather than clearing the
  /// previous one — the previous scene's systems (added in its own
  /// `populate`) would otherwise keep running against the new scene's
  /// entities, a class of bug a fresh `World` rules out entirely.
  Future<_LoadedGame> _load(Scene scene) async {
    await _ensureDefaultFontLoaded();
    final world = World(
      width: widget.game.config.worldWidth,
      height: widget.game.config.worldHeight,
    );
    registerCoreComponents(world);
    registerFlutterComponents(world);
    world.addSystem(SceneTransitionSystem());
    await scene.populate(world, _sceneController, _gameState);

    final atlasRegistry = await scene.loadAssets();
    await _registerPackedAtlas(atlasRegistry);
    final camera = scene.createCamera(world);
    final inputController = widget.game.createInputController();
    return _LoadedGame(world, atlasRegistry, camera, inputController, scene);
  }

  /// Registers `GameConfig.packedAtlasId`'s packed sprite sheet into
  /// [atlasRegistry], decoding it once (cached in [_packedAtlasFuture])
  /// and reusing that same `SpriteAtlas` — the decoded `ui.Image` and
  /// its region map — across every scene rather than re-decoding per
  /// load. A no-op when packed-atlas config isn't fully set, when
  /// [usePackedAtlas] is off, or when [atlasRegistry] already has
  /// something registered under this id (a scene's own `loadAssets`
  /// wins over the auto-registration, e.g. to override just this one
  /// scene during development).
  Future<void> _registerPackedAtlas(AtlasRegistry atlasRegistry) async {
    final config = widget.game.config;
    final id = config.packedAtlasId;
    final imagePath = config.packedAtlasImage;
    final manifestPath = config.packedAtlasManifest;
    if (!usePackedAtlas || id == null || imagePath == null || manifestPath == null) {
      return;
    }
    if (atlasRegistry.has(id)) return;

    _packedAtlasFuture ??= SpriteAtlas.loadFromAssets(
      imageAssetPath: imagePath,
      manifestAssetPath: manifestPath,
    );
    atlasRegistry.register(id, await _packedAtlasFuture!);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android clears an immersive SystemUiMode the moment the app loses
    // focus (backgrounded, a system dialog, etc.) -- re-applying it here
    // is what makes `fullscreen` stick across a resume instead of only
    // working until the very first interruption. Unconditional (not
    // gated by pauseOnBackground below), since a game that doesn't pause
    // in the background still needs this reapplied on resume.
    if (state == AppLifecycleState.resumed) {
      widget.game.config.applyFullscreen();
    }

    if (!widget.game.config.pauseOnBackground) return;
    final shouldPause = state != AppLifecycleState.resumed;
    if (shouldPause == _paused) return;
    setState(() => _paused = shouldPause);
    shouldPause ? widget.game.onPause() : widget.game.onResume();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LoadedGame>(
      future: _future,
      builder: (context, snapshot) {
        // A `Scene.populate`/`loadAssets` exception otherwise vanishes
        // completely -- `FutureBuilder` only exposes it via
        // `snapshot.error`, and the `loaded == null` branch below can't
        // tell "still loading" apart from "failed to load" without this,
        // so a broken scene (a malformed level asset, a null-asserted
        // component that isn't actually present) just hangs on the
        // loading screen forever with zero diagnostic -- found live
        // debugging exactly that hang, which cost real time to track
        // down blind before adding this. `FlutterError.reportError`
        // (not a bare `print`) so it goes through whatever error
        // reporting the embedding app has already configured, the same
        // as a framework-caught build error would.
        if (snapshot.hasError && !identical(_reportedErrorFor, _future)) {
          _reportedErrorFor = _future;
          FlutterError.reportError(FlutterErrorDetails(
            exception: snapshot.error!,
            stack: snapshot.stackTrace,
            library: 'engine_flutter',
            context: ErrorDescription('while loading a Scene in GameRunner'),
          ));
        }
        final loaded = snapshot.data;
        if (loaded == null) {
          return ColoredBox(
            color: widget.game.config.backgroundColor,
            child: widget.game.buildLoadingScreen(context),
          );
        }
        final overlay = _overlay;
        final engineView = RepaintBoundary(
          key: _engineViewRepaintKey,
          child: EngineView(
            world: loaded.world,
            atlasRegistry: loaded.atlasRegistry,
            camera: loaded.camera,
            inputController: loaded.inputController,
            cameraFollowEntity: loaded.scene.cameraFollowEntity(loaded.world),
            backgroundColor: widget.game.config.backgroundColor,
            paused: _paused || overlay != null,
            // Forced off in a real release build regardless of what
            // game_config.json says -- these are debugging aids, not
            // something a shipped build should ever be able to leak
            // (a config file left with one of these true by accident,
            // the common way this actually happens, otherwise ships
            // fps/tick/entity-count text or collider outlines to real
            // players). kReleaseMode is a compile-time constant Dart
            // tree-shakes the disabled branch from entirely in a release
            // build, not a runtime check with any cost.
            showFpsOverlay: !kReleaseMode && widget.game.config.showFpsOverlay,
            showColliderDebug: !kReleaseMode && widget.game.config.showColliderDebug,
            showPerformanceOverlay: !kReleaseMode && widget.game.config.showPerformanceOverlay,
            showAutoTileBitmask: !kReleaseMode &&
                (widget.game.config.showAutoTileBitmask || loaded.scene.showAutoTileBitmask),
            ambientBrightness:
                loaded.scene.ambientBrightness ?? widget.game.config.ambientBrightness,
            dayNightCycle: loaded.scene.dayNightCycle,
            maxFps: widget.game.config.maxFps,
            frameStats: widget.game.frameStats,
            singlePassLighting: widget.game.config.singlePassLighting,
            // No taps while an overlay is up -- it alone should be
            // interactive, so the paused scene underneath can't be
            // accidentally poked through it.
            onWorldTap: overlay == null
                ? (worldPosition) =>
                    loaded.scene.handleTap(loaded.world, _sceneController, worldPosition)
                : null,
            // Call scene's update method after each world step for per-frame logic
            onPostTick: (dt, world) => loaded.scene.update(dt, world),
          ),
        );

        final controller = loaded.inputController;
        // No controls at all while an overlay (e.g. a pause menu) is up
        // -- the base scene is frozen then, so they'd do nothing --  and
        // none for the current scene (base or overlay) when it opts out
        // via `Scene.showOnScreenControls` (every `ButtonMenuScene` does
        // — a menu is tap-driven, not movement/action-driven).
        final showControls = controller != null &&
            _shouldShowOnScreenControls() &&
            overlay == null &&
            loaded.scene.showOnScreenControls;
        final children = [
          engineView,
          if (showControls)
            OnScreenControls(
              controller: controller,
              verticalEnabled: widget.game.onScreenJoystickVertical,
              buttons: widget.game.onScreenButtons(),
              atlasRegistry: loaded.atlasRegistry,
            ),
          if (overlay != null)
            EngineView(
              world: overlay.world,
              atlasRegistry: overlay.atlasRegistry,
              camera: overlay.camera,
              // No keyboard focus for the overlay -- it's tap-driven
              // only, so it never steals focus the base scene would
              // otherwise want back once resumed.
              backgroundColor: const Color(0x99101018),
              maxFps: widget.game.config.maxFps,
              singlePassLighting: widget.game.config.singlePassLighting,
              onWorldTap: (worldPosition) =>
                  overlay.scene.handleTap(overlay.world, _sceneController, worldPosition),
              onPostTick: (dt, world) => overlay.scene.update(dt, world),
            ),
        ];
        return children.length == 1 ? engineView : Stack(children: children);
      },
    );
  }

  bool _shouldShowOnScreenControls() {
    switch (widget.game.config.onScreenControls) {
      case OnScreenControlsMode.on:
        return true;
      case OnScreenControlsMode.off:
        return false;
      case OnScreenControlsMode.auto:
        return defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS;
    }
  }
}

/// Whether `GameRunner` auto-registers `GameConfig.packedAtlasId`'s
/// packed sprite sheet (see its doc comment) into every loaded `Scene`.
/// `true` by default — a `--dart-define=USE_PACKED_ATLAS=false` build
/// (or `flutter run`/`flutter test` invocation) flips it off without
/// touching `game_config.json`, e.g. while iterating on art, where
/// re-running `game_agent pack-assets` after every image change is more
/// friction than just loading each image individually until the next
/// packed build. Meaningless unless `GameConfig.packedAtlasId` is also
/// set — this only gates *using* a packed atlas that's configured, it
/// can't summon one that isn't.
const bool usePackedAtlas = bool.fromEnvironment('USE_PACKED_ATLAS', defaultValue: true);

/// One-line entry point: `void main() => runGame(MyGame());`. Wraps
/// [GameRunner] in a `MaterialApp`/`Scaffold` sized to fill the screen —
/// use `GameRunner` directly if you need to embed the game inside a
/// larger app instead of owning the whole screen.
void runGame(Game game) {
  runApp(MaterialApp(
    title: game.config.title,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(scaffoldBackgroundColor: game.config.backgroundColor),
    home: Scaffold(
      backgroundColor: game.config.backgroundColor,
      body: GameRunner(game: game),
    ),
  ));
}
