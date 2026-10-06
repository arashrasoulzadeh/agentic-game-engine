import 'dart:io';

import 'package:engine_studio/src/code/code_editor_screen.dart';
import 'package:engine_studio/src/lsp/dart_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _editorTests();
  group('hoverText', () {
    test('reads markup, plain strings, and lists of either', () {
      expect(
        hoverText({'kind': 'markdown', 'value': 'class Hero'}),
        'class Hero',
      );
      expect(hoverText('plain'), 'plain');
      expect(
        hoverText([
          {'language': 'dart', 'value': 'void jump()'},
          'Makes the hero jump.',
        ]),
        'void jump()\n\nMakes the hero jump.',
      );
    });

    test('blank or missing contents give null, so nothing is shown', () {
      expect(hoverText(null), isNull);
      expect(hoverText({'kind': 'markdown', 'value': '   '}), isNull);
    });
  });

  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('hover');
    File(
      '${root.path}/pubspec.yaml',
    ).writeAsStringSync('name: demo\nenvironment:\n  sdk: ^3.0.0\n');
    Directory('${root.path}/lib').createSync();
    File('${root.path}/lib/hero.dart').writeAsStringSync(
      '/// A brave character.\nclass Hero {\n  void jump() {}\n}\n',
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'the real server describes the class under the cursor',
    () async {
      final session = await DartSession.open(root.path);
      final use = '${root.path}/lib/use.dart';
      session.openFile(
        use,
        "import 'hero.dart';\nvoid run() {\n  Hero h = Hero();\n}\n",
      );

      String? text;
      for (var attempt = 0; attempt < 40 && text == null; attempt++) {
        text = await session.hoverAt(use, 2, 4);
        if (text == null) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      expect(text, contains('Hero'));
      await session.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

void _editorTests() {
  testWidgets(
    'Ctrl+K with no language server shows no card and changes nothing',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('hover_editor');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/a.dart';
      File(path).writeAsStringSync('class A {}\n');
      await tester.pumpWidget(
        MaterialApp(
          home: CodeEditorScreen(filePath: path, useLanguageServer: false),
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.byKey(const Key('hover-card')), findsNothing);
    },
  );
}
