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

  group('collapsing', () {
    const source = 'void f() {\n  a();\n  b();\n}\nint x = 1;\n';

    Future<TextEditingController> open(WidgetTester tester) async {
      final path = '${root.path}/lib/fold.dart';
      File(path).writeAsStringSync(source);
      await tester.pumpWidget(
        MaterialApp(
          home: CodeEditorScreen(
            filePath: path,
            useLanguageServer: false,
            staticFoldingRanges: const [FoldingRange(0, 3)],
          ),
        ),
      );
      return tester
          .widget<TextField>(find.byKey(const Key('code-text')))
          .controller!;
    }

    testWidgets(
      'the indicator collapses the block: its lines leave the gutter, the text is untouched',
      (tester) async {
        final text = await open(tester);
        expect(find.byKey(const Key('gutter-line-4')), findsOneWidget);
        final fullHeight = tester
            .getSize(find.byKey(const Key('code-text')))
            .height;

        await tester.tap(find.byKey(const Key('fold-0')));
        await tester.pump();

        expect(
          find.byKey(const Key('gutter-line-1')),
          findsOneWidget,
          reason: 'the first line stays',
        );
        for (final hidden in [2, 3, 4]) {
          expect(
            find.byKey(Key('gutter-line-$hidden')),
            findsNothing,
            reason: 'line $hidden is folded away',
          );
        }
        expect(find.byKey(const Key('gutter-line-5')), findsOneWidget);
        expect(text.text, source, reason: 'folding must never change the file');
        expect(
          tester.getSize(find.byKey(const Key('code-text'))).height,
          fullHeight,
          reason: 'expands to fill its box',
        );
      },
    );

    testWidgets('tapping again expands it', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('fold-0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('fold-0')));
      await tester.pump();
      expect(find.byKey(const Key('gutter-line-3')), findsOneWidget);
    });

    testWidgets(
      'typing expands every fold, because their lines describe the old text',
      (tester) async {
        final text = await open(tester);
        await tester.tap(find.byKey(const Key('fold-0')));
        await tester.pump();
        expect(find.byKey(const Key('gutter-line-3')), findsNothing);

        text.value = TextEditingValue(
          text: 'x$source',
          selection: const TextSelection.collapsed(offset: 1),
        );
        await tester.pump();
        expect(find.byKey(const Key('gutter-line-3')), findsOneWidget);
      },
    );

    testWidgets('a caret that moves into folded text opens the fold', (
      tester,
    ) async {
      final text = await open(tester);
      await tester.tap(find.byKey(const Key('fold-0')));
      await tester.pump();
      expect(find.byKey(const Key('gutter-line-3')), findsNothing);

      text.selection = TextSelection.collapsed(offset: source.indexOf('b()'));
      await tester.pump();
      expect(find.byKey(const Key('gutter-line-3')), findsOneWidget);
    });
  });
}
