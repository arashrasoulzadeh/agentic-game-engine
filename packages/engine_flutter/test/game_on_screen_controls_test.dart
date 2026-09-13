import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptyScene extends Scene {
  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {}
}

class _ControllableGame extends Game {
  _ControllableGame(this.config);

  @override
  final GameConfig config;

  @override
  Scene createInitialScene() => _EmptyScene();

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

class _NoInputGame extends Game {
  @override
  GameConfig get config => const GameConfig(worldWidth: 200, worldHeight: 100);

  @override
  Scene createInitialScene() => _EmptyScene();
}
