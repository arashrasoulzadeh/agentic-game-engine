import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TapScene extends Scene {
  late SceneController scenes;
  final taps = <Offset>[];
  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {
    this.scenes = scenes;
  }
  @override
  void handleTap(World world, SceneController scenes, Offset worldPosition) {
    taps.add(worldPosition);
  }
}

class TapGame extends Game {
  final TapScene scene;
  TapGame(this.scene);
  @override
  GameConfig get config => const GameConfig(
    worldWidth: 800, worldHeight: 600, onScreenControls: OnScreenControlsMode.off);
  @override
  Scene createInitialScene() => scene;
}

void main() {
  testWidgets('taps route only to the overlay until it is dismissed', (tester) async {
    final scene = TapScene();
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: TapGame(scene))));
    await tester.pump();
    await tester.pump();
    await tester.tapAt(const Offset(100, 100));
    expect(scene.taps, [const Offset(100, 100)]);
    final overlay = TapScene();
    scene.scenes.pushOverlay(overlay);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.tapAt(const Offset(200, 150));
    expect(overlay.taps, [const Offset(200, 150)]);
    expect(scene.taps, hasLength(1));
    overlay.scenes.popOverlay();
    await tester.pump();
    await tester.tapAt(const Offset(300, 200));
    expect(scene.taps, [const Offset(100, 100), const Offset(300, 200)]);
    expect(overlay.taps, hasLength(1));
  });

  testWidgets('replacing FrameStats redirects subsequent frame measurements', (tester) async {
    final world = World(width: 800, height: 600);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    final first = FrameStats(), second = FrameStats();
    final camera = Camera(), atlas = AtlasRegistry();
    Widget view(FrameStats? stats) => MaterialApp(home: EngineView(
      world: world, atlasRegistry: atlas, camera: camera, frameStats: stats));
    await tester.pumpWidget(view(first));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(first.frameMs, 16);
    await tester.pumpWidget(view(second));
    await tester.pump(const Duration(milliseconds: 20));
    expect(second.frameMs, 20);
    expect(first.frameMs, 16);
    await tester.pumpWidget(view(null));
    await tester.pump(const Duration(milliseconds: 25));
    expect(second.frameMs, 20);
  });
}
