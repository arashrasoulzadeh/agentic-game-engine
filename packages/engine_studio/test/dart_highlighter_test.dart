import 'package:engine_studio/src/code/dart_highlighter.dart';
import 'package:engine_studio/src/code/marks.dart';
import 'package:flutter_test/flutter_test.dart';

DartTokenKind? _kindOf(List<DartToken> tokens, String text) =>
    tokens.where((t) => t.text == text).map((t) => t.kind).firstOrNull;

void main() {
  test(
    'the tokens rebuild the source exactly, so colouring never changes the text',
    () {
      const source =
          "class Hero extends Actor {\n  // jumps\n  final s = 'hi'; /* x */ var n = 3.5;\n}";
      final rebuilt = tokenizeDart(source).map((t) => t.text).join();
      expect(rebuilt, source);
    },
  );

  test('classifies keywords, types, strings, numbers, and comments', () {
    final tokens = tokenizeDart(
      "class Hero { var n = 3; String s = 'x'; // note\n}",
    );
    expect(_kindOf(tokens, 'class'), DartTokenKind.keyword);
    expect(_kindOf(tokens, 'Hero'), DartTokenKind.type);
    expect(_kindOf(tokens, '3'), DartTokenKind.number);
    expect(_kindOf(tokens, "'x'"), DartTokenKind.string);
    expect(_kindOf(tokens, '// note'), DartTokenKind.comment);
    expect(_kindOf(tokens, 'n'), DartTokenKind.plain);
  });

  test(
    'a keyword inside a string or a comment is not coloured as a keyword',
    () {
      final tokens = tokenizeDart("var s = 'class'; // return");
      expect(_kindOf(tokens, "'class'"), DartTokenKind.string);
      expect(_kindOf(tokens, '// return'), DartTokenKind.comment);
    },
  );

  test('an unterminated string stops at the end of its line', () {
    final tokens = tokenizeDart("var s = 'open\nclass X");
    expect(
      _kindOf(tokens, 'class'),
      DartTokenKind.keyword,
      reason: 'the next line is not swallowed by the open quote',
    );
  });

  test('empty source gives no tokens', () {
    expect(tokenizeDart(''), isEmpty);
  });

  test(
    'setting marks or searchMarks to an equal value does not notify listeners',
    () {
      final controller = DartHighlightController(text: 'var x = 1;');
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.marks = [const TextMark(0, 3, kind: MarkKind.error)];
      expect(notifications, 1);
      controller.marks = [const TextMark(0, 3, kind: MarkKind.error)];
      expect(notifications, 1, reason: 'an equal value is a no-op');

      controller.searchMarks = [
        const TextMark(4, 5, kind: MarkKind.searchMatch),
      ];
      expect(notifications, 2);
      controller.searchMarks = [
        const TextMark(4, 5, kind: MarkKind.searchMatch),
      ];
      expect(notifications, 2, reason: 'an equal value is a no-op');

      controller.bracketMarks = [const TextMark(0, 1, kind: MarkKind.bracket)];
      expect(notifications, 3);
      controller.bracketMarks = [const TextMark(0, 1, kind: MarkKind.bracket)];
      expect(notifications, 3, reason: 'an equal value is a no-op');
    },
  );

  test(
    'a listener that resets searchMarks to the same value does not recurse '
    '(regression: this froze the editor with a StackOverflowError)',
    () {
      final controller = DartHighlightController(text: 'var x = 1;');
      controller.addListener(() {
        controller.searchMarks = [
          const TextMark(0, 3, kind: MarkKind.searchMatch),
        ];
      });
      expect(
        () => controller.searchMarks = [
          const TextMark(0, 3, kind: MarkKind.searchMatch),
        ],
        returnsNormally,
      );
    },
  );
}
