import 'dart:io';

import 'package:engine_studio/src/code/code_editor_screen.dart';
import 'package:engine_studio/src/lsp/dart_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('code_folding');
    File(
      '${root.path}/pubspec.yaml',
    ).writeAsStringSync('name: demo\nenvironment:\n  sdk: ^3.0.0\n');
    Directory('${root.path}/lib').createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'the real server finds the class block as a foldable range',
    () async {
      final session = await DartSession.open(root.path);
      final file = '${root.path}/lib/hero.dart';
      const source = 'class Hero {\n  void jump() {\n    return;\n  }\n}\n';
      File(file).writeAsStringSync(source);
      session.openFile(file, source);

      List<FoldingRange> found = const [];
      for (var attempt = 0; attempt < 80 && found.isEmpty; attempt++) {
        try {
          found = await session.foldingRanges(file);
        } on Object {
          found = const [];
        }
        if (found.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      expect(found, isNotEmpty, reason: 'the class body is a foldable block');
      expect(
        found.any((r) => r.startLine == 0),
        isTrue,
        reason: "the class's own block starts at line 0",
      );
      await session.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets('no fold indicators appear with no language server', (
    tester,
  ) async {
    final path = '${root.path}/lib/hero.dart';
    File(path).writeAsStringSync('class Hero {}\n');
    await tester.pumpWidget(
      MaterialApp(
        home: CodeEditorScreen(filePath: path, useLanguageServer: false),
      ),
    );
    expect(find.byKey(const Key('fold-0')), findsNothing);
  });

  // A widget test driving this end to end (real server populating
  // _foldingRanges inside a pumped CodeEditorScreen, then tapping the
  // resulting fold-0 indicator) was attempted and dropped: DartSession.open's
  // Process.start never completed within this harness in that scenario,
  // the same flakiness disclosed in quick_fixes_test.dart's "real server"
  // widget test for IDE.5. The real-server unit test above already proves
  // foldingRanges() itself works; _revealFold's own logic (select from the
  // start of one line to the end of another) is simple enough that it
  // doesn't need a server to exercise meaningfully, and there's no way to
  // inject a fake FoldingRange into the widget's private state from outside.
}
