import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Scene extends Scene {
  _Scene(this.name, this.log);
  final String name;
  final List<String> log;
  late SceneController scenes;
  final taps = <Offset>[];

  @override
  Future<void> populate(
    World world,
    SceneController scenes,
    GameState state,
  ) async {
    this.scenes = scenes;
  }

  @override
  void handleTap(World world, SceneController scenes, Offset p) => taps.add(p);
  @override
  void onEnter(World world) => log.add('enter $name');
  @override
  void onExit(World world) => log.add('exit $name');
}

class _Game extends Game {
  _Game(this.scene);
  final Scene scene;
  @override
  GameConfig get config => const GameConfig(
    worldWidth: 800,
    worldHeight: 600,
    onScreenControls: OnScreenControlsMode.off,
  );
  @override
  Scene createInitialScene() => scene;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

void main() {
  testWidgets('overlays stack: taps go to the top, pop reveals the one below', (
    tester,
  ) async {
    final log = <String>[];
    final base = _Scene('base', log);
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: _Game(base))));
    await _settle(tester);

    final pause = _Scene('pause', log), confirm = _Scene('confirm', log);
    base.scenes.pushOverlay(pause);
    await _settle(tester);
    base.scenes.pushOverlay(confirm);
    await _settle(tester);

    await tester.tapAt(const Offset(100, 100));
    expect(confirm.taps, hasLength(1));
    expect(pause.taps, isEmpty);

    confirm.scenes.popOverlay();
    await _settle(tester);
    await tester.tapAt(const Offset(120, 120));
    expect(pause.taps, hasLength(1));
    expect(base.taps, isEmpty, reason: 'base stays frozen under the pause');

    pause.scenes.popOverlay();
    await _settle(tester);
    await tester.tapAt(const Offset(130, 130));
    expect(base.taps, hasLength(1));
  });

  testWidgets('onEnter/onExit fire once each, in order, including drops', (
    tester,
  ) async {
    final log = <String>[];
    final base = _Scene('base', log);
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: _Game(base))));
    await _settle(tester);
    expect(log, ['enter base']);

    final pause = _Scene('pause', log), next = _Scene('next', log);
    base.scenes.pushOverlay(pause);
    await _settle(tester);
    expect(log, ['enter base', 'enter pause']);

    pause.scenes.popOverlay();
    await _settle(tester);
    expect(log.last, 'exit pause');

    base.scenes.pushOverlay(pause);
    await _settle(tester);
    log.clear();
    base.scenes.loadScene(next);
    await _settle(tester);
    expect(log, containsAll(['exit pause', 'exit base', 'enter next']));
    expect(log.where((e) => e == 'exit base'), hasLength(1));
  });
}
