import 'dart:ui' as ui;

import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(4, 4);
}

void main() {
  test('OnScreenButtonSpec default constructor has no sprite fields set', () {
    const spec = OnScreenButtonSpec('jump', 'JUMP');
    expect(spec.label, 'JUMP');
    expect(spec.atlasId, isNull);
    expect(spec.region, isNull);
    expect(spec.diameter, 64);
    expect(spec.shape, BoxShape.circle);
  });

  test('OnScreenButtonSpec.custom accepts full customization', () {
    const spec = OnScreenButtonSpec.custom(
      'attack',
      atlasId: 'ui',
      region: 'attack_idle',
      pressedRegion: 'attack_pressed',
      diameter: 80,
      shape: BoxShape.rectangle,
      borderRadius: BorderRadius.all(Radius.circular(12)),
      idleColor: Color(0xFF112233),
      pressedColor: Color(0xFF445566),
    );

    expect(spec.atlasId, 'ui');
    expect(spec.region, 'attack_idle');
    expect(spec.pressedRegion, 'attack_pressed');
    expect(spec.diameter, 80);
    expect(spec.shape, BoxShape.rectangle);
  });

  testWidgets('falls back to color+label when atlasRegistry is not given', (tester) async {
    final controller = InputController();
    await tester.pumpWidget(_wrap(VirtualButton(
      controller: controller,
      spec: const OnScreenButtonSpec.custom('jump', label: 'JUMP', atlasId: 'ui', region: 'jump'),
    )));

    expect(find.text('JUMP'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(VirtualButton), matching: find.byType(CustomPaint)),
      findsNothing,
    );
  });

  testWidgets('renders the sprite region when the atlas is registered', (tester) async {
    final controller = InputController();
    final registry = AtlasRegistry();
    registry.register('ui', SpriteAtlas(await _tinyImage(), {
      'jump_idle': const Rect.fromLTWH(0, 0, 2, 2),
      'jump_pressed': const Rect.fromLTWH(2, 0, 2, 2),
    }));

    await tester.pumpWidget(_wrap(VirtualButton(
      controller: controller,
      atlasRegistry: registry,
      spec: const OnScreenButtonSpec.custom(
        'jump',
        atlasId: 'ui',
        region: 'jump_idle',
        pressedRegion: 'jump_pressed',
      ),
    )));

    expect(
      find.descendant(of: find.byType(VirtualButton), matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
    expect(find.text('JUMP'), findsNothing);
  });

  testWidgets('swaps to pressedRegion while held', (tester) async {
    final controller = InputController();
    final registry = AtlasRegistry();
    final image = await _tinyImage();
    registry.register('ui', SpriteAtlas(image, {
      'jump_idle': const Rect.fromLTWH(0, 0, 2, 2),
      'jump_pressed': const Rect.fromLTWH(2, 0, 2, 2),
    }));

    await tester.pumpWidget(_wrap(VirtualButton(
      controller: controller,
      atlasRegistry: registry,
      spec: const OnScreenButtonSpec.custom(
        'jump',
        atlasId: 'ui',
        region: 'jump_idle',
        pressedRegion: 'jump_pressed',
      ),
    )));

    expect(find.byKey(const ValueKey('jump_idle')), findsOneWidget);
    expect(find.byKey(const ValueKey('jump_pressed')), findsNothing);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(VirtualButton)));
    await tester.pump();

    expect(find.byKey(const ValueKey('jump_pressed')), findsOneWidget);
    expect(find.byKey(const ValueKey('jump_idle')), findsNothing);

    await gesture.up();
  });
}
