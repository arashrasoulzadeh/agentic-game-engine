import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity, Action;
import 'package:flutter_test/flutter_test.dart';

class _Counter extends System {
  int steps = 0;
  @override
  String get name => 'counter';
  @override
  void update(World world, double dt) => steps++;
}

void main() {
  group('SplitScreenLayout.rects', () {
    const size = Size(800, 600);

    test('one player fills the screen', () {
      expect(SplitScreenLayout.rects(1, size), [Offset.zero & size]);
    });

    test('two players split by screen shape, or as told', () {
      final wide = SplitScreenLayout.rects(2, const Size(800, 400), gap: 4);
      expect(wide[0], const Rect.fromLTWH(0, 0, 398, 400));
      expect(wide[1], const Rect.fromLTWH(402, 0, 398, 400));

      final tall = SplitScreenLayout.rects(2, const Size(400, 800), gap: 4);
      expect(tall[0].height, 398);
      expect(tall[1].top, 402);
      expect(tall[1].width, 400);

      final forced = SplitScreenLayout.rects(2, const Size(400, 800), orientation: SplitOrientation.sideBySide);
      expect(forced[1].left, greaterThan(0));
      expect(forced[1].top, 0);
      final stacked = SplitScreenLayout.rects(2, const Size(800, 400), orientation: SplitOrientation.stacked);
      expect(stacked[1].top, greaterThan(0));
    });

    test('three and four players use a 2x2 grid; the views never overlap or leave the screen', () {
      for (final n in [3, 4]) {
        final rects = SplitScreenLayout.rects(n, size, gap: 2);
        expect(rects.length, n);
        for (final r in rects) {
          expect(r.left >= 0 && r.top >= 0 && r.right <= size.width && r.bottom <= size.height, isTrue);
        }
        for (var i = 0; i < n; i++) {
          for (var j = i + 1; j < n; j++) {
            expect(rects[i].overlaps(rects[j]), isFalse, reason: '$i vs $j of $n');
          }
        }
      }
      expect(SplitScreenLayout.rects(3, size)[2].top, greaterThan(0));
    });

    test('0 and 5 players are rejected', () {
      expect(() => SplitScreenLayout.rects(0, size), throwsRangeError);
      expect(() => SplitScreenLayout.rects(5, size), throwsRangeError);
    });
  });

  group('SplitScreenView', () {
    World world() {
      final w = World(width: 2000, height: 600);
      registerCoreComponents(w);
      registerFlutterComponents(w);
      return w;
    }

    testWidgets('steps the world once per frame no matter how many players watch', (tester) async {
      Future<int> stepsFor(int players) async {
        final w = world();
        final counter = _Counter();
        w.addSystem(counter);
        final entities = [for (var i = 0; i < players; i++) w.spawn()];
        for (final e in entities) {
          w.storeOf<Position>().set(e, Position(100.0 * (e + 1), 100));
        }
        await tester.pumpWidget(MaterialApp(
          home: SplitScreenView(
            world: w,
            atlasRegistry: AtlasRegistry(),
            cameras: [for (var i = 0; i < players; i++) Camera()],
            followEntities: entities,
          ),
        ));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpWidget(const SizedBox());
        return counter.steps;
      }

      final one = await stepsFor(1);
      final two = await stepsFor(2);
      final four = await stepsFor(4);
      expect(one, greaterThan(0));
      expect(two, one);
      expect(four, one);
    });

    testWidgets('each camera follows its own entity', (tester) async {
      final w = world();
      final a = w.spawn(), b = w.spawn();
      w.storeOf<Position>().set(a, Position(300, 200));
      w.storeOf<Position>().set(b, Position(1500, 400));
      final cams = [Camera(), Camera()];
      await tester.pumpWidget(MaterialApp(
        home: SplitScreenView(
          world: w,
          atlasRegistry: AtlasRegistry(),
          cameras: cams,
          followEntities: [a, b],
        ),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(cams[0].x, lessThan(cams[1].x));
      expect(cams[1].x, greaterThan(cams[0].x + 500));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('lays out one clipped view per player with a divider behind', (tester) async {
      final w = world();
      await tester.pumpWidget(MaterialApp(
        home: SplitScreenView(
          world: w,
          atlasRegistry: AtlasRegistry(),
          cameras: [Camera(), Camera(), Camera()],
          followEntities: const [null, null, null],
        ),
      ));
      expect(find.byType(EngineView), findsNWidgets(3));
      expect(find.byType(ClipRect), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('only the first controller gets keyboard focus; stepsWorld is false on the rest',
        (tester) async {
      final w = world();
      final c1 = InputController(), c2 = InputController();
      await tester.pumpWidget(MaterialApp(
        home: SplitScreenView(
          world: w,
          atlasRegistry: AtlasRegistry(),
          cameras: [Camera(), Camera()],
          followEntities: const [null, null],
          inputControllers: [c1, c2],
        ),
      ));
      final views = tester.widgetList<EngineView>(find.byType(EngineView)).toList();
      expect(views[0].inputController, same(c1));
      expect(views[1].inputController, isNull);
      expect(views.map((v) => v.stepsWorld), [true, false]);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
