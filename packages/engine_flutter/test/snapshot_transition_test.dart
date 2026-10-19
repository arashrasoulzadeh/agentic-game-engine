import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _solid(Color color, {int w = 64, int h = 64}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = color,
  );
  return recorder.endRecording().toImage(w, h);
}

/// Renders [painter] to RGBA bytes at 64x64.
Future<Uint8List> _render(CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(ui.Canvas(recorder), const Size(64, 64));
  final image = await recorder.endRecording().toImage(64, 64);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

int _alpha(Uint8List rgba, int x, int y) => rgba[(y * 64 + x) * 4 + 3];

double _coverage(Uint8List rgba) {
  var covered = 0;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] > 127) covered++;
  }
  return covered / (rgba.length / 4);
}

void main() {
  group('SceneTransitionType', () {
    test('only fade and iris are world-based', () {
      for (final t in SceneTransitionType.values) {
        expect(
          t.usesSnapshot,
          !(t == SceneTransitionType.fade || t == SceneTransitionType.iris),
          reason: t.name,
        );
      }
    });

    test('new types round-trip through config JSON', () {
      for (final t in SceneTransitionType.values) {
        final back = SceneTransitionConfig.fromJson(
          SceneTransitionConfig(type: t).toJson(),
        );
        expect(back.type, t);
      }
    });

    test('a snapshot-type SceneTransition spawns no world components', () {
      final w = World(width: 100, height: 100);
      registerCoreComponents(w);
      registerFlutterComponents(w);
      final t = SceneTransition(
        config: const SceneTransitionConfig(
          type: SceneTransitionType.slideLeft,
          duration: 0.1,
        ),
        covering: true,
      )..start(w);
      expect(w.entities.count, 0);
      expect(t.update(1, w), isTrue);
    });
  });

  group('SnapshotTransitionPainter', () {
    testWidgets('slide moves the snapshot off in the named direction', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final img = await _solid(Colors.red);
        Future<Uint8List> at(SceneTransitionType type, double p) => _render(
          SnapshotTransitionPainter(snapshot: img, type: type, progress: p),
        );

        var px = await at(SceneTransitionType.slideLeft, 0.5);
        expect(_alpha(px, 10, 32), 255);
        expect(_alpha(px, 54, 32), 0);

        px = await at(SceneTransitionType.slideRight, 0.5);
        expect(_alpha(px, 10, 32), 0);
        expect(_alpha(px, 54, 32), 255);

        px = await at(SceneTransitionType.slideUp, 0.5);
        expect(_alpha(px, 32, 10), 255);
        expect(_alpha(px, 32, 54), 0);

        px = await at(SceneTransitionType.slideDown, 0.5);
        expect(_alpha(px, 32, 10), 0);
        expect(_alpha(px, 32, 54), 255);

        expect(_coverage(await at(SceneTransitionType.slideLeft, 0)), 1);
        expect(_coverage(await at(SceneTransitionType.slideLeft, 1)), 0);
      });
    });

    testWidgets('crossfade fades the snapshot linearly', (tester) async {
      await tester.runAsync(() async {
        final img = await _solid(Colors.red);
        final half = await _render(
          SnapshotTransitionPainter(
            snapshot: img,
            type: SceneTransitionType.crossfade,
            progress: 0.5,
          ),
        );
        expect(_alpha(half, 32, 32), closeTo(128, 3));
        final start = await _render(
          SnapshotTransitionPainter(
            snapshot: img,
            type: SceneTransitionType.crossfade,
            progress: 0,
          ),
        );
        expect(_alpha(start, 32, 32), 255);
        final end = await _render(
          SnapshotTransitionPainter(
            snapshot: img,
            type: SceneTransitionType.crossfade,
            progress: 1,
          ),
        );
        expect(_alpha(end, 32, 32), 0);
      });
    });

    testWidgets(
      'pixel dissolve removes blocks gradually and deterministically',
      (tester) async {
        await tester.runAsync(() async {
          final img = await _solid(Colors.red);
          Future<Uint8List> at(double p, {int seed = 1}) => _render(
            SnapshotTransitionPainter(
              snapshot: img,
              type: SceneTransitionType.pixelDissolve,
              progress: p,
              pixelSize: 4,
              seed: seed,
            ),
          );
          expect(_coverage(await at(0)), 1);
          expect(_coverage(await at(1)), 0);
          expect(_coverage(await at(0.5)), closeTo(0.5, 0.15));
          expect(
            _coverage(await at(0.25)),
            greaterThan(_coverage(await at(0.75))),
          );
          expect(await at(0.5), await at(0.5));
          expect(await at(0.5, seed: 1), isNot(await at(0.5, seed: 2)));
        });
      },
    );

    test('dissolveThreshold is stable, in [0, 1) and well spread', () {
      final values = <double>[
        for (var r = 0; r < 20; r++)
          for (var c = 0; c < 20; c++)
            SnapshotTransitionPainter.dissolveThreshold(c, r, 7),
      ];
      expect(values.every((v) => v >= 0 && v < 1), isTrue);
      expect(
        SnapshotTransitionPainter.dissolveThreshold(3, 4, 7),
        SnapshotTransitionPainter.dissolveThreshold(3, 4, 7),
      );
      expect(values.where((v) => v < 0.5).length, inInclusiveRange(150, 250));
    });

    testWidgets('world-based types paint nothing from a snapshot', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final img = await _solid(Colors.red);
        for (final t in [SceneTransitionType.fade, SceneTransitionType.iris]) {
          final px = await _render(
            SnapshotTransitionPainter(snapshot: img, type: t, progress: 0),
          );
          expect(_coverage(px), 0, reason: t.name);
        }
      });
    });
  });

  group('SnapshotTransition widget', () {
    testWidgets(
      'runs for its duration, then calls onDone once, ignoring pointers',
      (tester) async {
        late ui.Image img;
        await tester.runAsync(() async => img = await _solid(Colors.blue));
        var done = 0;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SnapshotTransition(
              snapshot: img,
              config: const SceneTransitionConfig(
                type: SceneTransitionType.crossfade,
                duration: 0.3,
              ),
              onDone: () => done++,
            ),
          ),
        );
        expect(find.byKey(const Key('snapshot-transition')), findsOneWidget);
        expect(
          tester
              .widget<IgnorePointer>(find.byType(IgnorePointer).first)
              .ignoring,
          isTrue,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(done, 0);
        await tester.pump(const Duration(milliseconds: 250));
        expect(done, 1);
        await tester.pump(const Duration(milliseconds: 500));
        expect(done, 1);
      },
    );
  });

  group('GameRunner integration', () {
    testWidgets(
      'loadSceneWithTransition(slide) swaps the scene and clears the overlay when done',
      (tester) async {
        final first = _Scene('first');
        final second = _Scene('second');
        await tester.pumpWidget(
          MaterialApp(home: GameRunner(game: _Game(first))),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));

        await tester.runAsync(() async {
          first.scenes.loadSceneWithTransition(
            second,
            transition: const SceneTransitionConfig(
              type: SceneTransitionType.slideLeft,
              duration: 0.2,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        await tester.pump();
        expect(second.populated, isTrue);
        expect(find.byKey(const Key('snapshot-transition')), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const Key('snapshot-transition')), findsNothing);
      },
    );
  });
}

class _Scene extends Scene {
  _Scene(this.label);
  final String label;
  late SceneController scenes;
  bool populated = false;
  @override
  Future<void> populate(
    World world,
    SceneController scenes,
    GameState state,
  ) async {
    this.scenes = scenes;
    populated = true;
  }
}

class _Game extends Game {
  _Game(this.scene);
  final Scene scene;
  @override
  GameConfig get config => const GameConfig(
    worldWidth: 200,
    worldHeight: 200,
    onScreenControls: OnScreenControlsMode.off,
  );
  @override
  Scene createInitialScene() => scene;
}
