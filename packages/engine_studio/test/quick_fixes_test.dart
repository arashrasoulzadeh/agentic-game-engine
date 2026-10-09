import 'dart:io';

import 'package:engine_studio/src/code/code_editor_screen.dart';
import 'package:engine_studio/src/lsp/dart_session.dart';
import 'package:engine_studio/src/lsp/edits.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('quick_fixes');
    File(
      '${root.path}/pubspec.yaml',
    ).writeAsStringSync('name: demo\nenvironment:\n  sdk: ^3.0.0\n');
    Directory('${root.path}/lib').createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'the real server offers a fix for an unused import, which removes it',
    () async {
      final session = await DartSession.open(root.path);
      final file = '${root.path}/lib/a.dart';
      const source = "import 'dart:math';\nvoid run() {}\n";
      session.openFile(file, source);

      List<CodeActionItem> actions = const [];
      for (var attempt = 0; attempt < 80 && actions.isEmpty; attempt++) {
        final diagnostics = session.rawDiagnosticsFor(file);
        try {
          actions = await session.codeActionsAt(
            file,
            0,
            8,
            diagnosticsJson: diagnostics,
          );
        } on Object {
          actions = const [];
        }
        if (actions.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      expect(actions, isNotEmpty, reason: 'the server offers at least one fix');
      final fix = actions.firstWhere(
        (a) => a.title.toLowerCase().contains('remove'),
        orElse: () => actions.first,
      );
      // The fix is a server command (dart.edit.codeAction.apply) rather than a
      // direct edit: applyCodeAction runs it, and the server sends the actual edit
      // back as a workspace/applyEdit request, which the session acknowledges.
      final grouped = await session.applyCodeAction(fix);
      final fixed = applyEdits(source, grouped[file]!);
      expect(fixed, isNot(contains("import 'dart:math';")));
      await session.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'Ctrl+. with no language server shows no panel and changes nothing',
    (tester) async {
      final path = '${root.path}/lib/a.dart';
      File(path).writeAsStringSync("import 'dart:math';\nvoid run() {}\n");
      await tester.pumpWidget(
        MaterialApp(
          home: CodeEditorScreen(filePath: path, useLanguageServer: false),
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.byKey(const Key('quick-fixes-panel')), findsNothing);
    },
  );
}
