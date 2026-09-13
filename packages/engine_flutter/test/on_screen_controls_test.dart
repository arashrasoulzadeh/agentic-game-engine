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
