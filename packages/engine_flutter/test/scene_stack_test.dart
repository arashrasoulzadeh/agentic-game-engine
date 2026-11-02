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
  sceneStackPushPopTests();
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

class _Counter extends _Scene {
  _Counter(super.name, super.log);
  late World world;
  @override
  Future<void> populate(
    World world,
    SceneController scenes,
    GameState state,
  ) async {
    await super.populate(world, scenes, state);
    this.world = world;
    registerCoreComponents(world);
    world.spawnAt(1, 2);
  }
}

void sceneStackPushPopTests() {
  testWidgets('pushScene keeps the old world alive and popScene restores it', (
    tester,
  ) async {
    final log = <String>[];
    final base = _Counter('base', log);
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: _Game(base))));
    await _settle(tester);
    final baseWorld = base.world;
    baseWorld.spawnAt(9, 9);

    final shop = _Counter('shop', log);
    base.scenes.pushScene(shop);
    await _settle(tester);
    expect(log, ['enter base', 'enter shop'], reason: 'no exit on suspend');
    expect(identical(shop.world, baseWorld), isFalse);

    shop.scenes.popScene();
    await _settle(tester);
    expect(log.last, 'exit shop');
    expect(
      baseWorld.componentsOf<Position>().length,
      2,
      reason: 'the suspended world kept its entities',
    );

    await tester.tapAt(const Offset(50, 50));
    expect(base.taps, hasLength(1));
    base.scenes.popScene();
    await _settle(tester);
    expect(
      base.taps,
      hasLength(1),
      reason: 'popping with nothing suspended is a no-op',
    );
  });

  testWidgets('a suspended scene gets its overlays back', (tester) async {
    final log = <String>[];
    final base = _Scene('base', log);
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: _Game(base))));
    await _settle(tester);
    final pause = _Scene('pause', log);
    base.scenes.pushOverlay(pause);
    await _settle(tester);
    final map = _Scene('map', log);
    base.scenes.pushScene(map);
    await _settle(tester);
    map.scenes.popScene();
    await _settle(tester);
    await tester.tapAt(const Offset(60, 60));
    expect(pause.taps, hasLength(1));
    expect(base.taps, isEmpty);
  });
}
