import 'dart:ui' as ui;

import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('VirtualJoystick', () {
    testWidgets('dragging right sets "right", releasing clears it', (tester) async {
      final controller = InputController();
      await tester.pumpWidget(_wrap(VirtualJoystick(controller: controller)));

      final center = tester.getCenter(find.byType(VirtualJoystick));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();

      expect(controller.state.isPressed('right'), isTrue);
      expect(controller.state.isPressed('left'), isFalse);

      await gesture.up();
      await tester.pump();
      expect(controller.state.isPressed('right'), isFalse);
    });

    testWidgets('dragging left sets "left"', (tester) async {
      final controller = InputController();
      await tester.pumpWidget(_wrap(VirtualJoystick(controller: controller)));

      final center = tester.getCenter(find.byType(VirtualJoystick));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();

      expect(controller.state.isPressed('left'), isTrue);
      await gesture.up();
    });

    testWidgets('vertical movement is ignored unless verticalEnabled', (tester) async {
      final controller = InputController();
      await tester.pumpWidget(_wrap(VirtualJoystick(controller: controller)));

      final center = tester.getCenter(find.byType(VirtualJoystick));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();

      expect(controller.state.isPressed('up'), isFalse);
      await gesture.up();
    });

    testWidgets('verticalEnabled: true sets "up"/"down"', (tester) async {
      final controller = InputController();
      await tester.pumpWidget(
        _wrap(VirtualJoystick(controller: controller, verticalEnabled: true)),
      );

      final center = tester.getCenter(find.byType(VirtualJoystick));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();

      expect(controller.state.isPressed('up'), isTrue);
      await gesture.up();
    });

    testWidgets('dragging past baseRadius clamps the knob offset', (tester) async {
      final controller = InputController();
      await tester.pumpWidget(_wrap(VirtualJoystick(controller: controller)));

      final center = tester.getCenter(find.byType(VirtualJoystick));
      final gesture = await tester.startGesture(center);
      // Default baseRadius is 50 -- 200px is well past it, exercising
      // the clamp-to-baseRadius branch instead of just testing the
      // unclamped, still-inside-the-circle case the other drag tests use.
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();

      expect(controller.state.isPressed('right'), isTrue);
      await gesture.up();
    });

    testWidgets('reversing drag direction clears the old action and sets the new one',
        (tester) async {
      final controller = InputController();
      await tester.pumpWidget(_wrap(VirtualJoystick(controller: controller)));

      final center = tester.getCenter(find.byType(VirtualJoystick));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(controller.state.isPressed('right'), isTrue);

      // Reverses direction within the same gesture -- exercises the
      // branch that clears a no-longer-active action (`right`) instead
      // of only ever adding a fresh one.
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump();
      expect(controller.state.isPressed('right'), isFalse);
      expect(controller.state.isPressed('left'), isTrue);

      await gesture.up();
    });

    testWidgets('small movement within the deadzone sets nothing', (tester) async {
      final controller = InputController();
      await tester.pumpWidget(_wrap(VirtualJoystick(controller: controller)));

      final center = tester.getCenter(find.byType(VirtualJoystick));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(2, 0));
      await tester.pump();

      expect(controller.state.pressedActions, isEmpty);
      await gesture.up();
    });
  });

  group('VirtualButton', () {
    testWidgets('press and release toggles the action', (tester) async {
      final controller = InputController();
      await tester.pumpWidget(_wrap(VirtualButton(
        controller: controller,
        spec: const OnScreenButtonSpec('jump', 'JUMP'),
      )));

      final center = tester.getCenter(find.byType(VirtualButton));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      expect(controller.state.isPressed('jump'), isTrue);

      await gesture.up();
      await tester.pump();
      expect(controller.state.isPressed('jump'), isFalse);
    });

    testWidgets('a cancelled gesture releases the action via onTapCancel', (tester) async {
      final controller = InputController();
      await tester.pumpWidget(_wrap(VirtualButton(
        controller: controller,
        spec: const OnScreenButtonSpec('jump', 'JUMP'),
      )));

      final center = tester.getCenter(find.byType(VirtualButton));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      expect(controller.state.isPressed('jump'), isTrue);

      await gesture.cancel();
      await tester.pump();
      expect(controller.state.isPressed('jump'), isFalse);
    });

    testWidgets('OnScreenButtonSpec.custom works as a non-const value too', (tester) async {
      final controller = InputController();
      final spec = OnScreenButtonSpec.custom('dash', label: 'DASH');
      await tester.pumpWidget(_wrap(VirtualButton(controller: controller, spec: spec)));

      expect(find.text('DASH'), findsOneWidget);
    });

    testWidgets(
        'repeated presses with a fixed sprite region trigger a shouldRepaint comparison',
        (tester) async {
      final controller = InputController();
      final registry = AtlasRegistry();
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
          .drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = const Color(0xFFFFFFFF));
      final image = await recorder.endRecording().toImage(4, 4);
      registry.register('ui', SpriteAtlas(image, {'jump': const Rect.fromLTWH(0, 0, 4, 4)}));

      // No pressedRegion -- activeRegion (and so the CustomPaint's key)
      // stays "jump" whether pressed or not, so pressing/releasing
      // rebuilds the SAME element with a NEW _SpritePainter instance
      // rather than swapping to a differently-keyed one, which is what
      // makes the framework actually call CustomPainter.shouldRepaint.
      await tester.pumpWidget(_wrap(VirtualButton(
        controller: controller,
        atlasRegistry: registry,
        spec: const OnScreenButtonSpec.custom('jump', atlasId: 'ui', region: 'jump'),
      )));

      final gesture = await tester.startGesture(tester.getCenter(find.byType(VirtualButton)));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    });
  });

  group('OnScreenControls', () {
    testWidgets('renders a joystick and the configured buttons', (tester) async {
      final controller = InputController();
      await tester.pumpWidget(_wrap(OnScreenControls(
        controller: controller,
        buttons: const [
          OnScreenButtonSpec('jump', 'JUMP'),
          OnScreenButtonSpec('dash', 'DASH'),
        ],
      )));

      expect(find.byType(VirtualJoystick), findsOneWidget);
      expect(find.byType(VirtualButton), findsNWidgets(2));
      expect(find.text('JUMP'), findsOneWidget);
      expect(find.text('DASH'), findsOneWidget);
    });
  });
}
