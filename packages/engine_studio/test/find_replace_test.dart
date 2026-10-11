import 'package:engine_studio/src/code/find_replace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('findMatches', () {
    test('finds every non-overlapping occurrence', () {
      final matches = findMatches('abcabcabc', 'abc');
      expect(matches, [
        const TextMatch(0, 3),
        const TextMatch(3, 6),
        const TextMatch(6, 9),
      ]);
    });

    test('is case-insensitive by default', () {
      expect(findMatches('Hello hello HELLO', 'hello').length, 3);
    });

    test('can be made case-sensitive', () {
      final matches = findMatches(
        'Hello hello HELLO',
        'hello',
        caseSensitive: true,
      );
      expect(matches, [const TextMatch(6, 11)]);
    });

    test('an empty query has no matches', () {
      expect(findMatches('anything', ''), isEmpty);
    });

    test('no occurrence gives an empty list', () {
      expect(findMatches('abc', 'xyz'), isEmpty);
    });
  });

  group('replaceAllMatches', () {
    test('replaces every occurrence', () {
      expect(replaceAllMatches('abcabcabc', 'abc', 'x'), 'xxx');
    });

    test('a replacement of different length still lines up', () {
      expect(replaceAllMatches('one two one', 'one', 'three'), 'three two three');
    });

    test('text with no matches is unchanged', () {
      expect(replaceAllMatches('abc', 'xyz', 'q'), 'abc');
    });

    test('is case-insensitive by default', () {
      expect(replaceAllMatches('Foo foo FOO', 'foo', 'bar'), 'bar bar bar');
    });
  });
}
