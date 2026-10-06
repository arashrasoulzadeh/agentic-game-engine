import 'package:engine_studio/src/code/dart_highlighter.dart';
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
}
