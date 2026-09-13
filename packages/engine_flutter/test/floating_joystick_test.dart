import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 400, height: 400, child: child),
      ),
    );

void main() {
  testWidgets('floating joystick (default) renders nothing before first touch',
      (tester) async {
    final controller = InputController();
    await tester.pumpWidget(_wrap(VirtualJoystick(controller: controller)));

    expect(
      find.descendant(of: find.byType(VirtualJoystick), matching: find.byType(Container)),
      findsNothing,
    );
  });

  testWidgets('floating joystick appears at the touch point, not a fixed corner',
      (tester) async {
    final controller = InputController();
    await tester.pumpWidget(_wrap(VirtualJoystick(controller: controller)));

    // Touch far from where a fixed-position joystick's base would sit
    // (bottom-left corner) -- if the joystick incorrectly used a fixed
    // origin instead of the touch point, this offset alone would
    // already register a direction with no movement at all.
    final farFromCorner = tester.getTopLeft(find.byType(VirtualJoystick)) +
        const Offset(300, 300);
    final gesture = await tester.startGesture(farFromCorner);
    await tester.pump();

    expect(controller.state.pressedActions, isEmpty);

    // Now confirm it actually renders (appeared) at the touch point.
    expect(
      find.descendant(of: find.byType(VirtualJoystick), matching: find.byType(Container)),
      findsWidgets,
    );

    await gesture.up();
    await tester.pump();

    // And disappears again after release.
    expect(
      find.descendant(of: find.byType(VirtualJoystick), matching: find.byType(Container)),
      findsNothing,
    );
  });

  testWidgets('floating: false keeps the classic always-visible joystick',
      (tester) async {
    final controller = InputController();
    await tester.pumpWidget(
      _wrap(VirtualJoystick(controller: controller, floating: false)),
    );

    expect(
      find.descendant(of: find.byType(VirtualJoystick), matching: find.byType(Container)),
      findsWidgets,
    );
  });
}
