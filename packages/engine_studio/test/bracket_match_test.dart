import 'package:engine_studio/src/code/bracket_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cursor right after an open bracket finds its close', () {
    const source = 'f(x)';
    // Cursor between '(' (index 1) and 'x' (index 2).
    expect(matchingBracket(source, 2), (1, 3));
  });

  test('cursor right before a close bracket finds its open', () {
    const source = 'f(x)';
    // Cursor between 'x' (index 2) and ')' (index 3).
    expect(matchingBracket(source, 3), (3, 1));
  });

  test('nested brackets of the same kind pair correctly', () {
    const source = '(a(b)c)';
    // Cursor right after the outer '(' (offset 1).
    final found = matchingBracket(source, 1);
    expect(found, (0, 6));
  });

  test('mismatched bracket kinds are not paired', () {
    const source = '(]';
    expect(matchingBracket(source, 1), isNull);
  });

  test('a bracket inside a string is not matched', () {
    const source = "var s = '(';";
    final found = matchingBracket(source, source.indexOf('(') + 1);
    expect(found, isNull);
  });

  test('a bracket inside a comment is not matched', () {
    const source = '// (\nvoid run() {}';
    final found = matchingBracket(source, source.indexOf('(') + 1);
    expect(found, isNull);
  });

  test('no bracket at or before the cursor gives nothing', () {
    const source = 'var x = 1;';
    expect(matchingBracket(source, 4), isNull);
  });

  test('an unbalanced bracket has no pair', () {
    const source = 'void run() {';
    final found = matchingBracket(source, 12);
    expect(found, isNull);
  });
}
