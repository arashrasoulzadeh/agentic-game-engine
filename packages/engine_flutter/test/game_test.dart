import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestGame extends Game {
  bool paused = false;
  bool resumed = false;

  @override
  GameConfig get config => const GameConfig(worldWidth: 200, worldHeight: 100);

  @override
  void populateWorld(World world) {}

  @override
  void onPause() => paused = true;

  @override
  void onResume() => resumed = true;
}

class _SlowLoadingGame extends _TestGame {
  @override
  Future<AtlasRegistry> loadAssets() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return AtlasRegistry();
  }
}

class _CustomLoadingScreenGame extends _SlowLoadingGame {
  @override
  Widget buildLoadingScreen(BuildContext context) =>
      const Center(child: Text('Loading my game...'));
}

void main() {
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
}
