import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart';

void main() {
  testWidgets('typing a command runs it and shows the output', (t) async {
    final console = DevConsole(worldOf: () => null);
    await t.pumpWidget(
      MaterialApp(home: Scaffold(body: DevConsoleOverlay(console: console))),
    );
    await t.enterText(find.byType(TextField), 'echo hello');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.text('hello'), findsOneWidget);
    expect(console.history, ['echo hello']);
  });

  testWidgets('the complete button fills the only match', (t) async {
    final console = DevConsole(worldOf: () => null);
    await t.pumpWidget(
      MaterialApp(home: Scaffold(body: DevConsoleOverlay(console: console))),
    );
    await t.enterText(find.byType(TextField), 'hitst');
    await t.tap(find.byIcon(Icons.keyboard_tab));
    await t.pump();
    expect(find.text('hitstop'), findsOneWidget);
  });
}
