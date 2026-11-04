import 'package:flutter/material.dart' hide Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' as z;
import 'package:zarvan_flutter/src/register_components.dart';

World _menu() {
  final w = World(width: 400, height: 300);
  registerCoreComponents(w);
  registerFlutterComponents(w);
  EntityId at(double x, double y) {
    final e = w.spawn();
    w.componentsOf<Position>().set(e, Position(x, y));
    return e;
  }

  final b = at(200, 150);
  w.componentsOf<Button>().set(b, Button('start'));
  w.componentsOf<ButtonHitBox>().set(b, ButtonHitBox(120, 40));
  w.componentsOf<z.Text>().set(at(200, 150), z.Text('Start game'));
  final b2 = at(200, 220);
  w.componentsOf<Button>().set(b2, Button('quit'));
  w.componentsOf<ButtonHitBox>().set(b2, ButtonHitBox(120, 40));
  w.componentsOf<z.Text>().set(at(20, 20), z.Text('Score 5'));
  w.componentsOf<z.Text>().set(at(20, 60), z.Text(''));
  return w;
}

void main() {
  test(
    'buttons take the label of the text inside them; HUD text is read-only',
    () {
      final t = z.semanticTargets(
        _menu(),
        z.Camera(x: 200, y: 150),
        const Size(400, 300),
      );
      expect(t.map((e) => e.label), ['Score 5', 'Start game', 'quit']);
      expect(t.map((e) => e.isButton), [false, true, true]);
      final start = t[1];
      expect(start.actionId, 'start');
      expect(start.rect.center, const Offset(200, 150));
      expect(start.rect.size, const Size(120, 40));
    },
  );

  test('camera zoom and pan move and scale the targets', () {
    final t = z.semanticTargets(
      _menu(),
      z.Camera(x: 100, y: 150, zoom: 2),
      const Size(400, 300),
    );
    final start = t.firstWhere((e) => e.actionId == 'start');
    expect(start.rect.center, const Offset(400, 150));
    expect(start.rect.width, 240);
  });

  testWidgets('exposes buttons to assistive tech and activates them', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    final world = _menu();
    String? pressed;
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 300),
          accessibleNavigation: true,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: z.WorldSemantics(
            worldOf: () => world,
            cameraOf: () => z.Camera(x: 200, y: 150),
            onActivate: (id) => pressed = id,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Start game'), findsOneWidget);
    t.semantics.tap(find.semantics.byLabel('Start game'));
    expect(pressed, 'start');
    handle.dispose();
  });

  testWidgets('adds nothing when no assistive tech is active', (t) async {
    final world = _menu();
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(400, 300)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: z.WorldSemantics(
            worldOf: () => world,
            cameraOf: () => z.Camera(),
            onActivate: (_) {},
            child: const SizedBox(key: Key('c')),
          ),
        ),
      ),
    );
    expect(find.byType(Semantics), findsNothing);
    expect(find.byKey(const Key('c')), findsOneWidget);
  });
}
