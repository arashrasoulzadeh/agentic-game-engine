import 'package:engine_studio/src/code/dart_highlighter.dart';
import 'package:engine_studio/src/code/folding.dart';
import 'package:engine_studio/src/lsp/dart_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _code = 'void f() {\n  a;\n  b;\n}\nint x;\nclass C {\n  m();\n}';

void main() {
  test(
    'lineEnd finds the newline that ends a line, or the end of the text',
    () {
      expect(lineEnd(_code, 0), 10);
      expect(lineEnd(_code, 3), _code.indexOf('}') + 1);
      expect(lineEnd(_code, 7), _code.length);
      expect(lineEnd(_code, 99), _code.length);
    },
  );

  test(
    'a collapsed fold hides from its first line\'s end to its last line\'s end',
    () {
      final hidden = hiddenRangesFor(
        _code,
        const [FoldingRange(0, 3), FoldingRange(5, 7)],
        {0},
      );
      expect(hidden, hasLength(1));
      expect(
        _code.substring(hidden.single.start, hidden.single.end),
        '\n  a;\n  b;\n}',
      );
      expect(
        _code.substring(0, hidden.single.start),
        'void f() {',
        reason: 'the first line stays visible',
      );
    },
  );

  test('uncollapsed, one-line and out-of-range folds hide nothing', () {
    expect(hiddenRangesFor(_code, const [FoldingRange(0, 3)], {}), isEmpty);
    expect(hiddenRangesFor(_code, const [FoldingRange(2, 2)], {2}), isEmpty);
    expect(hiddenRangesFor('x', const [FoldingRange(0, 5)], {0}), isEmpty);
  });

  test('nested folds merge into one hidden range', () {
    final hidden = hiddenRangesFor(
      _code,
      const [FoldingRange(0, 3), FoldingRange(1, 2)],
      {0, 1},
    );
    expect(hidden, hasLength(1));
    expect(
      hiddenLinesFor(const [FoldingRange(0, 3), FoldingRange(1, 2)], {0, 1}),
      {1, 2, 3},
    );
  });

  test('insideHidden is true for offsets the player cannot see', () {
    const hidden = [TextRange(start: 10, end: 20)];
    expect(
      insideHidden(hidden, 10),
      isFalse,
      reason: 'the end of the visible first line',
    );
    expect(insideHidden(hidden, 11), isTrue);
    expect(insideHidden(hidden, 20), isTrue);
    expect(insideHidden(hidden, 21), isFalse);
  });

  testWidgets('a folded range takes no vertical space but stays in the text', (
    tester,
  ) async {
    final c = DartHighlightController(text: _code);
    const strut = StrutStyle(fontSize: 0.01, height: 0.01);
    Future<double> height() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: TextField(
                  controller: c,
                  maxLines: null,
                  strutStyle: strut,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(TextField)).height;
    }

    final full = await height();
    c.folded = hiddenRangesFor(_code, const [FoldingRange(0, 3)], {0});
    final folded = await height();
    expect(folded, lessThan(full - 40), reason: 'three lines disappeared');
    expect(c.text, _code, reason: 'the file text is untouched');
    c.folded = const [];
    expect(await height(), full);
  });
}
