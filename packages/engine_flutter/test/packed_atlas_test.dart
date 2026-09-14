import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A rasterized `Picture`, not a decoded codec image -- unlike
/// `SpriteAtlas.loadFromAssets` (`ui.instantiateImageCodec`), this
/// resolves through the normal test rasterizer without needing
/// `tester.runAsync`, so a scene using it is safe to drive with plain
/// `tester.pump()` calls the same as any other widget test in this
/// suite.
Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(4, 4);
}

class _EmptyScene extends Scene {
  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {}
}

class _NoPackedConfigGame extends Game {
  _NoPackedConfigGame(this._scene);
  final Scene _scene;

  @override
  GameConfig get config => const GameConfig(worldWidth: 200, worldHeight: 100);

  @override
  Scene createInitialScene() => _scene;
}

/// A game with `GameConfig.packedAtlasId` set but no `flutter/assets`
/// mock installed at all -- if `_registerPackedAtlas` ever tried to
/// actually load it, `rootBundle.load` would throw (no handler for a
/// real, unmocked asset channel in a test binding), which is exactly
/// what this file's one test below is checking never happens for a
/// game that leaves packed-atlas config unset.
///
/// Coverage for `_registerPackedAtlas` actually registering/caching a
/// real decoded atlas lives in `SpriteAtlas.loadFromAssets`'s own test
/// in `sprite_atlas_test.dart` (a plain `test()`, not `testWidgets()`)
/// — `ui.instantiateImageCodec`'s real async codec work needs
/// `tester.runAsync` to resolve inside a `testWidgets` fake-async zone,
/// which deadlocks against `GameRunner`'s own continuously-rescheduling
/// `Ticker` (it never reaches the quiescence `runAsync` waits for) when
/// the two are combined; not worth chasing further just to duplicate
/// coverage `SpriteAtlas`'s own test already provides for the loading
/// mechanics themselves. What's specific to `GameRunner` here (the
/// config-gating, not-touching-the-bundle-when-unset behavior) doesn't
/// need real image bytes to verify.
class _PackedConfigGame extends Game {
  _PackedConfigGame(this._scene);
  final Scene _scene;

  @override
  GameConfig get config => const GameConfig(
        worldWidth: 200,
        worldHeight: 100,
        packedAtlasId: 'packed',
        packedAtlasImage: 'assets/packed/atlas.png',
        packedAtlasManifest: 'assets/packed/atlas.json',
      );

  @override
  Scene createInitialScene() => _scene;
}

/// Registers its own atlas under the same id the game's packed-atlas
/// config uses, via a rasterized `Picture` rather than a real decoded
/// asset -- proves `_registerPackedAtlas` checks `AtlasRegistry.has`
/// and skips loading entirely (so no real, unmocked asset bundle call
/// happens at all) when a scene already claimed this id itself.
class _OverridingAtlasScene extends Scene {
  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {}

  @override
  Future<AtlasRegistry> loadAssets() async {
    final registry = AtlasRegistry();
    registry.register('packed', SpriteAtlas(await _tinyImage(), {'own': Rect.zero}));
    return registry;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('no packed-atlas config (default) never touches the asset bundle at all',
      (tester) async {
    final game = _NoPackedConfigGame(_EmptyScene());
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: game)));
    await tester.pump();
    await tester.pump();

    final view = tester.widget<EngineView>(find.byType(EngineView));
    expect(view.atlasRegistry.has('packed'), isFalse);
  });

  testWidgets(
      'GameConfig.packedAtlasId set but no mocked asset bundle never resolves to a '
      'rendered EngineView -- proves _registerPackedAtlas actually attempts the load '
      'when config is present (the mirror image of the test above), since '
      "rootBundle.load's failure becomes the loading Future's error and "
      "GameRunner's FutureBuilder just keeps showing the loading screen for an "
      'errored future rather than throwing into the widget tree', (tester) async {
    final game = _PackedConfigGame(_EmptyScene());
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: game)));
    await tester.pump();
    await tester.pump();

    expect(find.byType(EngineView), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
      "a scene's own loadAssets registration under the same id wins over "
      'auto-registration -- and, since no flutter/assets mock is installed, this '
      'also proves the auto-registration is skipped entirely rather than attempted '
      'and clobbering the result', (tester) async {
    final game = _PackedConfigGame(_OverridingAtlasScene());
    await tester.pumpWidget(MaterialApp(home: GameRunner(game: game)));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    final view = tester.widget<EngineView>(find.byType(EngineView));
    expect(view.atlasRegistry.resolve('packed').regionFor('own'), Rect.zero);
  });
}
