import 'package:engine_core/engine_core.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'camera.dart';
import 'engine_view.dart';
import 'game_config.dart';
import 'input.dart';
import 'on_screen_controls.dart';
import 'register_components.dart';
import 'sprite_atlas.dart';

/// The top-level entry point a game implements. Extend this instead of
/// hand-wiring `World`/`Ticker`/`CustomPaint` yourself — `runGame` handles
/// orientation, asset loading, app-lifecycle pause/resume, and the
/// render loop; you only define *what* the game is.
abstract class Game {
  GameConfig get config;

  /// Adds systems and spawns entities on [world]. `GameRunner` has
  /// already constructed `world` (sized from `config`) and registered
  /// the core + Flutter built-in components on it — forgetting to
  /// register `Sprite`/`Position`/etc. is a common footgun this design
  /// removes entirely; you only ever add your own game-specific pieces.
  void populateWorld(World world);

  /// Loads sprite atlases (or other async setup) before the first frame.
  /// Defaults to an empty registry for games with no sprites yet.
  Future<AtlasRegistry> loadAssets() async => AtlasRegistry();

  /// Defaults to a camera centered on the world. Override to start
  /// somewhere else or follow a specific entity from frame one.
  Camera createCamera(World world) =>
      Camera(x: world.width / 2, y: world.height / 2);

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

  /// Shown while `populateWorld`/`loadAssets` are running, before the
  /// first frame can render. Defaults to a centered spinner on the
  /// configured background color — override for a branded splash
  /// screen/logo instead.
  Widget buildLoadingScreen(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _LoadedGame {
  final World world;
  final AtlasRegistry atlasRegistry;
  final Camera camera;
  final InputController? inputController;

  _LoadedGame(this.world, this.atlasRegistry, this.camera, this.inputController);
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
  late final Future<_LoadedGame> _future;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.game.config.applyOrientation();
    _future = _load();
  }

  Future<_LoadedGame> _load() async {
    final world = World(
      width: widget.game.config.worldWidth,
      height: widget.game.config.worldHeight,
    );
    registerCoreComponents(world);
    registerFlutterComponents(world);
    widget.game.populateWorld(world);

    final atlasRegistry = await widget.game.loadAssets();
    final camera = widget.game.createCamera(world);
    final inputController = widget.game.createInputController();
    return _LoadedGame(world, atlasRegistry, camera, inputController);
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
        final engineView = EngineView(
          world: loaded.world,
          atlasRegistry: loaded.atlasRegistry,
          camera: loaded.camera,
          inputController: loaded.inputController,
          cameraFollowEntity: widget.game.cameraFollowEntity(loaded.world),
          backgroundColor: widget.game.config.backgroundColor,
          paused: _paused,
          showFpsOverlay: widget.game.config.showFpsOverlay,
        );

        final controller = loaded.inputController;
        if (controller == null || !_shouldShowOnScreenControls()) {
          return engineView;
        }
        return Stack(
          children: [
            engineView,
            OnScreenControls(
              controller: controller,
              verticalEnabled: widget.game.onScreenJoystickVertical,
              buttons: widget.game.onScreenButtons(),
            ),
          ],
        );
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
