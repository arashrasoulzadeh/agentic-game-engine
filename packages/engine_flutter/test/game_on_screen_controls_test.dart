import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptyScene extends Scene {
  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {}
}

/// A minimal `ButtonMenuScene` — exists only to prove its inherited
/// `showOnScreenControls == false` actually suppresses `OnScreenControls`
/// when `GameRunner` renders it, the way a real title/pause screen does.
class _NoOpMenuScene extends ButtonMenuScene {
  @override
  List<MenuButtonSpec> buttons() =>
      const [MenuButtonSpec(label: 'RESUME', actionId: 'resume')];

  @override
  void onButtonPressed(String actionId, SceneController scenes) {}
}

class _ControllableGame extends Game {
  _ControllableGame(this.config, [Scene? initialScene]) : _initialScene = initialScene;

  @override
  final GameConfig config;

  final Scene? _initialScene;

  @override
  Scene createInitialScene() => _initialScene ?? _EmptyScene();

  @override
  InputController? createInputController() => InputController();
}

Future<void> _pumpLoaded(WidgetTester tester, Game game) async {
  await tester.pumpWidget(MaterialApp(home: GameRunner(game: game)));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('mode "on" shows controls regardless of platform', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final game = _ControllableGame(const GameConfig(
      worldWidth: 200,
      worldHeight: 100,
      onScreenControls: OnScreenControlsMode.on,
    ));
    await _pumpLoaded(tester, game);

    expect(find.byType(OnScreenControls), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mode "off" hides controls even on a mobile platform', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final game = _ControllableGame(const GameConfig(
      worldWidth: 200,
      worldHeight: 100,
      onScreenControls: OnScreenControlsMode.off,
    ));
    await _pumpLoaded(tester, game);

    expect(find.byType(OnScreenControls), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mode "auto" shows controls on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final game = _ControllableGame(const GameConfig(worldWidth: 200, worldHeight: 100));
    await _pumpLoaded(tester, game);

    expect(find.byType(OnScreenControls), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mode "auto" hides controls on desktop platforms', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final game = _ControllableGame(const GameConfig(worldWidth: 200, worldHeight: 100));
    await _pumpLoaded(tester, game);

    expect(find.byType(OnScreenControls), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mode "on" still hides controls for a scene that opts out (ButtonMenuScene)',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final game = _ControllableGame(
      const GameConfig(worldWidth: 200, worldHeight: 100, onScreenControls: OnScreenControlsMode.on),
      _NoOpMenuScene(),
    );
    await _pumpLoaded(tester, game);

    expect(find.byType(OnScreenControls), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('pushing an overlay hides controls even though the base scene wants them',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final markerScene = _ControlsMarkerScene();
    final game = _ControllableGame(
      const GameConfig(worldWidth: 200, worldHeight: 100, onScreenControls: OnScreenControlsMode.on),
      markerScene,
    );
    await _pumpLoaded(tester, game);
    expect(find.byType(OnScreenControls), findsOneWidget);

    markerScene.scenes!.pushOverlay(_NoOpMenuScene());
    await tester.pump();
    await tester.pump();

    expect(find.byType(OnScreenControls), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('no controls at all when createInputController returns null',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final game = _NoInputGame();
    await _pumpLoaded(tester, game);

    expect(find.byType(OnScreenControls), findsNothing);
    expect(find.byType(EngineView), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}

/// A normal (non-menu) `Scene` that records the `SceneController` it was
/// handed, so a test can trigger `pushOverlay` from outside `populate`.
class _ControlsMarkerScene extends Scene {
  SceneController? scenes;

  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {
    this.scenes = scenes;
  }
}

class _NoInputGame extends Game {
  @override
  GameConfig get config => const GameConfig(worldWidth: 200, worldHeight: 100);

  @override
  Scene createInitialScene() => _EmptyScene();
}
