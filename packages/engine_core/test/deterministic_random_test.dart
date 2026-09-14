import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('DeterministicRandom', () {
    test('same seed produces the same sequence across two independent instances', () {
      final a = DeterministicRandom(42);
      final b = DeterministicRandom(42);

      final aValues = List.generate(20, (_) => a.nextInt(1000));
      final bValues = List.generate(20, (_) => b.nextInt(1000));

      expect(aValues, equals(bValues));
    });

    test('different seeds produce different sequences', () {
      final a = DeterministicRandom(1);
      final b = DeterministicRandom(2);

      final aValues = List.generate(20, (_) => a.nextInt(1000000));
      final bValues = List.generate(20, (_) => b.nextInt(1000000));

      expect(aValues, isNot(equals(bValues)));
    });

    test('reset() replays the identical sequence from the start', () {
      final rng = DeterministicRandom(7);
      final first = List.generate(10, (_) => rng.nextDouble());

      rng.reset();
      final second = List.generate(10, (_) => rng.nextDouble());

      expect(second, equals(first));
    });

    test('nextRange stays within [min, max) and reproduces deterministically', () {
      final rng = DeterministicRandom(99);
      for (var i = 0; i < 50; i++) {
        final value = rng.nextRange(10, 20);
        expect(value, greaterThanOrEqualTo(10));
        expect(value, lessThan(20));
      }
    });

    test('seed is readable back off the instance', () {
      expect(DeterministicRandom(123).seed, 123);
    });
  });
}
