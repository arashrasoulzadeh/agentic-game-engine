import 'package:engine_studio/src/code/dart_highlighter.dart';
import 'package:engine_studio/src/code/marks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs rebuild the source exactly, with marks applied', () {
    const source = 'var x = nothere;';
    final runs = applyMarks(tokenizeDart(source), [
      const TextMark(8, 15, isError: true),
    ]);
    expect(runs.map((r) => r.text).join(), source);
  });

  test('the marked stretch is exactly the marked characters', () {
    final runs = applyMarks(tokenizeDart('var x = nothere;'), [
      const TextMark(8, 15, isError: true),
    ]);
    final marked = runs.where((r) => r.mark != null).map((r) => r.text).join();
    expect(marked, 'nothere');
  });

  test('a mark can cross a token boundary and keeps each token\'s colour', () {
    final runs = applyMarks(tokenizeDart("String a = 'hi';"), [
      const TextMark(7, 10, isError: false),
    ]);
    final marked = runs.where((r) => r.mark != null).toList();
    expect(marked.map((r) => r.text).join(), 'a =');
    expect(runs.firstWhere((r) => r.text == 'String').kind, DartTokenKind.type);
  });

  test('no marks gives back the tokens unchanged', () {
    final tokens = tokenizeDart('return 1;');
    final runs = applyMarks(tokens, const []);
    expect(
      runs.map((r) => r.text).toList(),
      tokens.map((t) => t.text).toList(),
    );
    expect(runs.every((r) => r.mark == null), isTrue);
  });
}
