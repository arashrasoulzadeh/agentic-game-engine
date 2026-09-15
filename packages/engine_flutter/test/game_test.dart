import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptyScene extends Scene {
  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {}
}

class _SlowLoadingScene extends Scene {
  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {}

  @override
  Future<AtlasRegistry> loadAssets() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return AtlasRegistry();
  }
}

class _TestGame extends Game {
  bool paused = false;
  bool resumed = false;

  @override
  GameConfig get config => const GameConfig(worldWidth: 200, worldHeight: 100);

  @override
  Scene createInitialScene() => _EmptyScene();

  @override
  void onPause() => paused = true;

  @override
  void onResume() => resumed = true;
}

class _SlowLoadingGame extends _TestGame {
  @override
  Scene createInitialScene() => _SlowLoadingScene();
}

class _CustomLoadingScreenGame extends _SlowLoadingGame {
  @override
  Widget buildLoadingScreen(BuildContext context) =>
      const Center(child: Text('Loading my game...'));
}

class _DefaultCallbacksGame extends Game {
  @override
  GameConfig get config => const GameConfig(worldWidth: 100, worldHeight: 100);

  @override
  Scene createInitialScene() => _EmptyScene();
}

class _FrameStatsGame extends _TestGame {
  final FrameStats stats = FrameStats();

  @override
  FrameStats get frameStats => stats;
}

void main() {
  testWidgets('Game.onPause/onResume default to no-ops', (tester) async {
    final game = _DefaultCallbacksGame();
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: game)));
    await tester.pump();
    await tester.pump();

    // Exercises the base-class no-op bodies directly -- GameRunner only
    // calls these on a lifecycle change, which _TestGame's override
    // already covers elsewhere; this proves the *default* Game itself
    // (no override) doesn't throw.
    game.onPause();
    game.onResume();
  });

  testWidgets('runGame wraps GameRunner in a MaterialApp/Scaffold', (tester) async {
    final game = _DefaultCallbacksGame();
    runGame(game);
    await tester.pump();
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(GameRunner), findsOneWidget);
  });

  testWidgets('Game.frameStats defaults to null and GameRunner does not require one',
      (tester) async {
    final game = _TestGame();
    expect(game.frameStats, isNull);
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: game)));
    await tester.pump();
    await tester.pump();

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets("GameRunner keeps a Game's own FrameStats instance updated every frame",
      (tester) async {
    final game = _FrameStatsGame();
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: game)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(game.stats.stepMs, greaterThanOrEqualTo(0),
        reason: 'the exact same instance returned by frameStats was passed into '
            'EngineView and actually written to by a real rendered frame');
    expect(game.stats.paintMs, greaterThanOrEqualTo(0));
  });

  testWidgets('GameRunner loads the game and renders EngineView', (tester) async {
    final game = _TestGame();
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: game)));
    // EngineView's Ticker runs continuously by design, so pumpAndSettle
    // (which waits for frames to stop being scheduled) never converges —
    // pump explicitly instead: once to let the asset-loading Future
    // resolve, once more to let the resulting FutureBuilder rebuild.
    await tester.pump();
    await tester.pump();

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets('GameRunner calls onPause/onResume on app lifecycle changes',
      (tester) async {
    final game = _TestGame();
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: game)));
    // EngineView's Ticker runs continuously by design, so pumpAndSettle
    // (which waits for frames to stop being scheduled) never converges —
    // pump explicitly instead: once to let the asset-loading Future
    // resolve, once more to let the resulting FutureBuilder rebuild.
    await tester.pump();
    await tester.pump();

    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(game.paused, isTrue);

    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(game.resumed, isTrue);
  });

  testWidgets('shows the default loading screen until assets finish loading',
      (tester) async {
    final game = _SlowLoadingGame();
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: game)));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(EngineView), findsNothing);

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    expect(find.byType(EngineView), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('buildLoadingScreen can be overridden', (tester) async {
    final game = _CustomLoadingScreenGame();
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: game)));
    await tester.pump();

    expect(find.text('Loading my game...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Let the pending delayed Future resolve before the test ends, or
    // the test framework flags it as a leaked timer.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
  });

  testWidgets('SceneController.loadScene swaps the running World for a new scene',
      (tester) async {
    final firstScene = _MarkerScene('first');
    final game = _SwitchingGame(firstScene);
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: game)));
    await tester.pump();
    await tester.pump();

    expect(firstScene.markerId, isNotNull);
    final world = tester
        .widget<EngineView>(find.byType(EngineView))
        .world;
    expect(world.entities.count, 1);

    final secondScene = _MarkerScene('second');
    firstScene.scenes!.loadScene(secondScene);
    await tester.pump();
    await tester.pump();

    final newWorld = tester
        .widget<EngineView>(find.byType(EngineView))
        .world;
    // A brand-new World, not the same instance bulk-cleared -- proves
    // the switch didn't reuse/leak state from the old scene.
    expect(identical(newWorld, world), isFalse);
    expect(newWorld.entities.count, 1);
    expect(secondScene.markerId, isNotNull);
    expect(
      newWorld.storeOf<Sprite>().get(secondScene.markerId!)?.region,
      'second',
    );
  });

  testWidgets('GameState is the same instance across a loadScene switch, unlike World',
      (tester) async {
    final firstScene = _MarkerScene('first');
    final game = _SwitchingGame(firstScene);
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: game)));
    await tester.pump();
    await tester.pump();

    firstScene.state!.data['coinsCollected'] = 3;

    final secondScene = _MarkerScene('second');
    firstScene.scenes!.loadScene(secondScene);
    await tester.pump();
    await tester.pump();

    // The whole point of GameState (unlike World, which is deliberately
    // rebuilt fresh per scene -- see the test above) is that it's the
    // one thing carried forward untouched by a scene switch.
    expect(identical(secondScene.state, firstScene.state), isTrue);
    expect(secondScene.state!.data['coinsCollected'], 3);
  });

  testWidgets('SceneController.pushOverlay pauses the base scene without replacing its World',
      (tester) async {
    final baseScene = _MarkerScene('base');
    final game = _SwitchingGame(baseScene);
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: game)));
    await tester.pump();
    await tester.pump();

    final baseWorld = tester.widgetList<EngineView>(find.byType(EngineView)).single.world;

    final overlayScene = _MarkerScene('overlay');
    baseScene.scenes!.pushOverlay(overlayScene);
    await tester.pump();
    await tester.pump();

    final views = tester.widgetList<EngineView>(find.byType(EngineView)).toList();
    expect(views, hasLength(2));
    // The base scene's World is the exact same instance, and it's
    // paused -- pushOverlay must not rebuild/replace it the way
    // loadScene does, or "resume" wouldn't resume anything.
    final baseView = views.firstWhere((v) => identical(v.world, baseWorld));
    expect(baseView.paused, isTrue);
    expect(overlayScene.markerId, isNotNull);

    baseScene.scenes!.popOverlay();
    await tester.pump();
    await tester.pump();

    final afterPop = tester.widgetList<EngineView>(find.byType(EngineView)).single;
    expect(identical(afterPop.world, baseWorld), isTrue);
    expect(afterPop.paused, isFalse);
  });
}

/// Spawns exactly one entity (tagged via its `Sprite` region so tests
/// can tell scenes apart) and records the `SceneController` it was
/// handed, so a test can trigger a switch from outside `populate`.
class _MarkerScene extends Scene {
  _MarkerScene(this.label);

  final String label;
  SceneController? scenes;
  GameState? state;
  EntityId? markerId;

  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {
    this.scenes = scenes;
    this.state = state;
    markerId = world.spawn();
    world.storeOf<Sprite>().set(markerId!, Sprite('none', label));
  }
}

class _SwitchingGame extends Game {
  _SwitchingGame(this._initial);

  final Scene _initial;

  @override
  GameConfig get config => const GameConfig(worldWidth: 200, worldHeight: 100);

  @override
  Scene createInitialScene() => _initial;
}
