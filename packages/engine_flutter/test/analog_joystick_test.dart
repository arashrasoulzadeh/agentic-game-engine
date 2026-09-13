import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('analogOutput false leaves axis values unset', (tester) async {
    final controller = InputController();
    await tester.pumpWidget(_wrap(SizedBox(
      width: 200,
      height: 200,
      child: VirtualJoystick(controller: controller),
    )));

    final gesture = await tester.startGesture(const Offset(80, 80));
    await gesture.moveTo(const Offset(130, 80));
    await tester.pump();

    expect(controller.state.axis('moveX'), 0.0);
    await gesture.up();
  });

  testWidgets('analogOutput true reports continuous moveX/moveY and resets on release',
      (tester) async {
    final controller = InputController();
    await tester.pumpWidget(_wrap(SizedBox(
      width: 200,
      height: 200,
      child: VirtualJoystick(
        controller: controller,
        verticalEnabled: true,
        analogOutput: true,
        baseRadius: 50,
      ),
    )));

    final gesture = await tester.startGesture(const Offset(80, 80));
    await gesture.moveTo(const Offset(105, 80));
    await tester.pump();

    expect(controller.state.axis('moveX'), closeTo(0.5, 0.01));
    expect(controller.state.axis('moveY'), 0.0);

    await gesture.up();
    await tester.pump();

    expect(controller.state.axis('moveX'), 0.0);
    expect(controller.state.axis('moveY'), 0.0);
  });
}
