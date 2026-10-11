import 'package:engine_studio/src/code/auto_close.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('auto-closing an opener', () {
    test('typing ( inserts the matching ) right after the cursor', () {
      // Typed '(' after "f", cursor now at 2.
      expect(autoCloseResult('f', 'f(', 2), ('f()', 2));
    });

    test('typing { inserts the matching }', () {
      expect(autoCloseResult('', '{', 1), ('{}', 1));
    });

    test('typing a quote inserts the matching quote', () {
      expect(autoCloseResult('', '"', 1), ('""', 1));
    });

    test('a plain closer with nothing to skip over is left alone', () {
      expect(autoCloseResult('f(', 'f()', 3), isNull);
    });
  });

  group('typing through an auto-closed pair', () {
    test('typing ) right before an existing ) moves past it instead of '
        'inserting a duplicate', () {
      // Cursor was at offset 1 in "()" (between '(' and ')'), typed ')':
      // the raw keystroke makes the buffer "())" with cursor at 2.
      expect(autoCloseResult('()', '())', 2), ('()', 2));
    });

    test('typing a closing quote right before an existing one skips over it', () {
      expect(autoCloseResult('""', '"""', 2), ('""', 2));
    });
  });

  group('not a plain single-character insertion', () {
    test('a multi-character paste is left alone', () {
      expect(autoCloseResult('f', 'f(x)', 4), isNull);
    });

    test('a programmatic replace (format, rename, completion) is left alone', () {
      expect(autoCloseResult('var x=1;', 'var x = 1;', 10), isNull);
    });
  });

  test('typing a letter does nothing', () {
    expect(autoCloseResult('f', 'fo', 2), isNull);
  });
}
