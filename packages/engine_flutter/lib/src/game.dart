import 'package:engine_core/engine_core.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'camera.dart';
import 'engine_view.dart';
import 'game_config.dart';
import 'input.dart';
import 'on_screen_controls.dart';
import 'register_components.dart';
import 'scene.dart';
import 'sprite_atlas.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.game.config.applyOrientation();
    _sceneController.attach(
      loadScene: _loadScene,
      pushOverlay: _pushOverlay,
      popOverlay: _popOverlay,
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

  /// Builds a brand-new `World` for [scene] rather than clearing the
  /// previous one — the previous scene's systems (added in its own
  /// `populate`) would otherwise keep running against the new scene's
  /// entities, a class of bug a fresh `World` rules out entirely.
  Future<_LoadedGame> _load(Scene scene) async {
    final world = World(
      width: widget.game.config.worldWidth,
      height: widget.game.config.worldHeight,
    );
    registerCoreComponents(world);
    registerFlutterComponents(world);
    await scene.populate(world, _sceneController, _gameState);

    final atlasRegistry = await scene.loadAssets();
    final camera = scene.createCamera(world);
    final inputController = widget.game.createInputController();
    return _LoadedGame(world, atlasRegistry, camera, inputController, scene);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
        final loaded = snapshot.data;
        if (loaded == null) {
          return ColoredBox(
            color: widget.game.config.backgroundColor,
            child: widget.game.buildLoadingScreen(context),
          );
        }
        final overlay = _overlay;
        final engineView = EngineView(
          world: loaded.world,
          atlasRegistry: loaded.atlasRegistry,
          camera: loaded.camera,
          inputController: loaded.inputController,
          cameraFollowEntity: loaded.scene.cameraFollowEntity(loaded.world),
          backgroundColor: widget.game.config.backgroundColor,
          paused: _paused || overlay != null,
          showFpsOverlay: widget.game.config.showFpsOverlay,
          showColliderDebug: widget.game.config.showColliderDebug,
          // No taps while an overlay is up -- it alone should be
          // interactive, so the paused scene underneath can't be
          // accidentally poked through it.
          onWorldTap: overlay == null
              ? (worldPosition) =>
                  loaded.scene.handleTap(loaded.world, _sceneController, worldPosition)
              : null,
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
              onWorldTap: (worldPosition) =>
                  overlay.scene.handleTap(overlay.world, _sceneController, worldPosition),
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
