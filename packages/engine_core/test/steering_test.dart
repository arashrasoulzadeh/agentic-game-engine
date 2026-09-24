import 'dart:math' as math;

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('Steering primitives', () {

    group('seek', () {
      test('returns velocity directly toward target at maxSpeed', () {
        final from = Position(0, 0);
        final to = Position(100, 0);
        final v = seek(from, to, 50);

        expect(v.x, closeTo(50, 1e-9));
        expect(v.y, closeTo(0, 1e-9));
      });

      test('handles diagonal correctly', () {
        final from = Position(0, 0);
        final to = Position(100, 100);
        final v = seek(from, to, 100);

        expect(v.x, closeTo(70.710678, 1e-6));
        expect(v.y, closeTo(70.710678, 1e-6));
        expect(v.magnitude, closeTo(100, 1e-6));
      });

      test('returns zero when already at target', () {
        final from = Position(50, 50);
        final to = Position(50, 50);
        final v = seek(from, to, 100);

        expect(v.x, 0);
        expect(v.y, 0);
      });

      test('works with negative coordinates', () {
        final from = Position(-100, -100);
        final to = Position(-50, -50);
        final v = seek(from, to, 10);

        expect(v.x, closeTo(7.0710678, 1e-6));
        expect(v.y, closeTo(7.0710678, 1e-6));
      });
    });

    group('arrive', () {
      test('returns full maxSpeed outside slowRadius', () {
        final from = Position(0, 0);
        final to = Position(200, 0);
        final v = arrive(from, to, 50, 50);

        expect(v.x, closeTo(50, 1e-9));
        expect(v.y, closeTo(0, 1e-9));
      });

      test('scales speed down linearly inside slowRadius', () {
        final from = Position(0, 0);
        final slowRadius = 100.0;

        // At 50% of slowRadius, speed should be 50% of maxSpeed
        final v1 = arrive(from, Position(50, 0), 100.0, slowRadius);
        expect(v1.x, closeTo(50, 1e-9));

        // At 25% of slowRadius, speed should be 25% of maxSpeed
        final v2 = arrive(from, Position(25, 0), 100.0, slowRadius);
        expect(v2.x, closeTo(25, 1e-9));

        // At edge of slowRadius, speed = maxSpeed
        final v3 = arrive(from, Position(100, 0), 100.0, slowRadius);
        expect(v3.x, closeTo(100, 1e-9));
      });

      test('returns zero at target', () {
        final v = arrive(Position(0, 0), Position(0, 0), 100, 50);
        expect(v.x, 0);
        expect(v.y, 0);
      });

      test('never exceeds maxSpeed', () {
        final from = Position(0, 0);
        final to = Position(1000, 0);
        final v = arrive(from, to, 50, 100);

        expect(v.magnitude, lessThanOrEqualTo(50));
      });
    });

    group('wander', () {
      test('produces same sequence with same seed', () {
        final v1 = Velocity(50, 0);
        final r1 = DeterministicRandom(42);
        final w1 = wander(v1, 10, 50, r1);

        final v2 = Velocity(50, 0);
        final r2 = DeterministicRandom(42);
        final w2 = wander(v2, 10, 50, r2);

        expect(w1.x, w2.x);
        expect(w1.y, w2.y);
      });

      test('different seeds produce different results', () {
        final v = Velocity(50, 0);
        final w1 = wander(v, 10, 50, DeterministicRandom(42));
        final w2 = wander(v, 10, 50, DeterministicRandom(43));

        expect(w1.x == w2.x && w1.y == w2.y, isFalse);
      });

      test('result magnitude never exceeds maxSpeed', () {
        final v = Velocity(50, 0);
        final r = DeterministicRandom(42);

        for (int i = 0; i < 100; i++) {
          final w = wander(v, 20, 50, r);
          expect(w.magnitude, lessThanOrEqualTo(50 + 1e-9));
        }
      });

      test('jitter=0 returns same direction at maxSpeed', () {
        final v = Velocity(50, 0);
        final r = DeterministicRandom(42);
        final w = wander(v, 0, 50, r);

        expect(w.magnitude, closeTo(50, 1e-9));
        expect(w.angle, closeTo(0, 1e-9));
      });
    });

    group('VelocitySteering extension', () {
      test('angle returns correct value', () {
        expect(Velocity(1, 0).angle, 0);
        expect(Velocity(0, 1).angle, closeTo(math.pi / 2, 1e-9));
        expect(Velocity(-1, 0).angle, closeTo(math.pi, 1e-9));
        expect(Velocity(0, -1).angle, closeTo(-math.pi / 2, 1e-9));
        expect(Velocity(1, 1).angle, closeTo(math.pi / 4, 1e-9));
      });

      test('withSpeed preserves angle', () {
        final v = Velocity(3, 4); // magnitude 5, angle atan2(4,3)
        final scaled = v.withSpeed(10);

        expect(scaled.magnitude, closeTo(10, 1e-9));
        expect(scaled.angle, closeTo(v.angle, 1e-9));
      });

      test('withSpeed(0) returns zero velocity', () {
        final scaled = Velocity(100, 200).withSpeed(0);
        expect(scaled.x, 0);
        expect(scaled.y, 0);
      });
    });
  });
}