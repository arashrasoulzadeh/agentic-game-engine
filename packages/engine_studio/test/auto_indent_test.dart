import 'package:engine_studio/src/code/auto_indent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Enter on a plain line keeps the same leading whitespace', () {
    const text = '  var x = 1;';
    final (newText, cursor) = indentedNewline(text, text.length);
    expect(newText, '  var x = 1;\n  ');
    expect(cursor, newText.length);
  });

  test('Enter right after an unclosed opening brace indents one more level', () {
    const text = 'void run() {';
    final (newText, cursor) = indentedNewline(text, text.length);
    expect(newText, 'void run() {\n  ');
    expect(cursor, newText.length);
  });

  test(
    'Enter between an empty pair of braces splits it onto three lines',
    () {
      const text = 'void run() {}';
      // Cursor between '{' (index 11) and '}' (index 12).
      final (newText, cursor) = indentedNewline(text, 12);
      expect(newText, 'void run() {\n  \n}');
      expect(cursor, 'void run() {\n  '.length);
    },
  );

  test('an indented block still splits at its own indent level', () {
    const text = '  if (x) {}';
    final (newText, cursor) = indentedNewline(text, 10);
    expect(newText, '  if (x) {\n    \n  }');
    expect(cursor, '  if (x) {\n    '.length);
  });

  test('a custom indent unit is honoured', () {
    const text = 'void run() {';
    final (newText, _) = indentedNewline(text, text.length, indentUnit: '\t');
    expect(newText, 'void run() {\n\t');
  });

  test('no surrounding brackets just repeats the current indent', () {
    const text = '    foo();';
    final (newText, cursor) = indentedNewline(text, text.length);
    expect(newText, '    foo();\n    ');
    expect(cursor, newText.length);
  });
}
