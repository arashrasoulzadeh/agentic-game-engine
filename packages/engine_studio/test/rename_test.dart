import 'dart:io';

import 'package:engine_studio/src/code/code_editor_screen.dart';
import 'package:engine_studio/src/lsp/dart_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:engine_studio/src/lsp/edits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _editorTest();
  group('parseWorkspaceEdit', () {
    test('reads the "changes" map form, grouped by file', () {
      final grouped = parseWorkspaceEdit({
        'changes': {
          'file:///a.dart': [
            {
              'range': {
                'start': {'line': 0, 'character': 6},
                'end': {'line': 0, 'character': 10},
              },
              'newText': 'Champ',
            },
          ],
        },
      });
      expect(grouped.keys, ['/a.dart']);
      expect(grouped['/a.dart']!.single.newText, 'Champ');
    });

    test('reads the "documentChanges" list form', () {
      final grouped = parseWorkspaceEdit({
        'documentChanges': [
          {
            'textDocument': {'uri': 'file:///b.dart'},
            'edits': [
              {
                'range': {
                  'start': {'line': 1, 'character': 0},
                  'end': {'line': 1, 'character': 4},
                },
                'newText': 'Champ',
              },
            ],
          },
        ],
      });
      expect(grouped.keys, ['/b.dart']);
    });

    test('an empty or missing edit gives nothing', () {
      expect(parseWorkspaceEdit(null), isEmpty);
      expect(parseWorkspaceEdit({}), isEmpty);
    });
  });

  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('rename');
    File(
      '${root.path}/pubspec.yaml',
    ).writeAsStringSync('name: demo\nenvironment:\n  sdk: ^3.0.0\n');
    Directory('${root.path}/lib').createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'the real server renames a class everywhere it is used',
    () async {
      final session = await DartSession.open(root.path);
      final hero = '${root.path}/lib/hero.dart';
      final use = '${root.path}/lib/use.dart';
      const heroSource = 'class Hero {}\n';
      const useSource = "import 'hero.dart';\nvoid run() {\n  Hero();\n}\n";
      session.openFile(hero, heroSource);
      session.openFile(use, useSource);

      Map<String, List<TextEdit>> grouped = const {};
      for (var attempt = 0; attempt < 80 && grouped.length < 2; attempt++) {
        try {
          grouped = await session.renameAt(hero, 0, 6, 'Champion');
        } on Object {
          grouped = const {};
        }
        if (grouped.length < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      expect(grouped.keys, containsAll([hero, use]));
      expect(applyEdits(heroSource, grouped[hero]!), contains('Champion'));
      expect(applyEdits(useSource, grouped[use]!), contains('Champion()'));
      await session.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

void _editorTest() {
  testWidgets(
    'F2 renames the symbol in this buffer and offers to update the other file',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('rename_editor');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(
        '${dir.path}/pubspec.yaml',
      ).writeAsStringSync('name: demo\nenvironment:\n  sdk: ^3.0.0\n');
      Directory('${dir.path}/lib').createSync();
      final hero = '${dir.path}/lib/hero.dart';
      final use = '${dir.path}/lib/use.dart';
      File(hero).writeAsStringSync('class Hero {}\n');
      File(
        use,
      ).writeAsStringSync("import 'hero.dart';\nvoid run() {\n  Hero();\n}\n");

      await tester.pumpWidget(
        MaterialApp(
          home: CodeEditorScreen(filePath: hero, projectRoot: dir.path),
        ),
      );

      // Wait for the language server to start and finish its first analysis.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 3)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('code-text')));
      await tester.pump();
      _placeCursorOnHero(tester);

      bool renamed = false;
      for (var attempt = 0; attempt < 20 && !renamed; attempt++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pump(const Duration(milliseconds: 100));
        renamed = find.byKey(const Key('rename-input')).evaluate().isNotEmpty;
        if (!renamed) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 500)),
          );
          await tester.pump();
        }
      }
      expect(find.byKey(const Key('rename-input')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('rename-input')))
            .controller!
            .text,
        'Hero',
      );

      bool applied = false;
      for (var attempt = 0; attempt < 10 && !applied; attempt++) {
        await tester.enterText(
          find.byKey(const Key('rename-input')),
          'Champion',
        );
        await tester.tap(find.byKey(const Key('rename-confirm')));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 800)),
        );
        await tester.pump();
        applied = tester
            .widget<TextField>(find.byKey(const Key('code-text')))
            .controller!
            .text
            .contains('Champion');
        if (!applied) {
          // The server was not ready yet, so the rename silently did nothing.
          // Reopen the dialog (the symbol is still Hero) and try again.
          await tester.sendKeyEvent(LogicalKeyboardKey.f2);
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('code-text')))
            .controller!
            .text,
        contains('Champion'),
      );
      expect(
        find.byKey(Key('rename-file-${use.split('/').last}')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('rename-apply')));
      await tester.pump();
      expect(File(use).readAsStringSync(), contains('Champion()'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

void _placeCursorOnHero(WidgetTester tester) {
  final field = tester.state<EditableTextState>(find.byType(EditableText));
  final text = field.textEditingValue.text;
  final at = text.indexOf('Hero') + 2;
  field.userUpdateTextEditingValue(
    field.textEditingValue.copyWith(
      selection: TextSelection.collapsed(offset: at),
    ),
    SelectionChangedCause.tap,
  );
}
