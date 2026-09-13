import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveSolidCircleAabb', () {
    test('pushes out to the left when overlapping from the left side', () {
      final pos = Position(18, 50);
      final vel = Velocity(10, 0);

      final landed = resolveSolidCircleAabb(
        pos: pos,
        vel: vel,
        radius: 5,
        left: 20,
        right: 100,
        top: 0,
        bottom: 200,
      );

      expect(landed, isFalse);
      expect(pos.x, 20 - 5);
      expect(vel.x, 0);
    });

    test('pushes out to the right when overlapping from the right side', () {
      final pos = Position(102, 50);
      final vel = Velocity(-10, 0);

      final landed = resolveSolidCircleAabb(
        pos: pos,
        vel: vel,
        radius: 5,
        left: 0,
        right: 100,
        top: 0,
        bottom: 200,
      );

      expect(landed, isFalse);
      expect(pos.x, 100 + 5);
      expect(vel.x, 0);
    });

    test('no overlap is a no-op and returns false', () {
      final pos = Position(0, 0);
      final vel = Velocity(0, 0);

      final landed = resolveSolidCircleAabb(
        pos: pos,
        vel: vel,
        radius: 1,
        left: 100,
        right: 200,
        top: 100,
        bottom: 200,
      );

      expect(landed, isFalse);
      expect(pos.x, 0);
      expect(pos.y, 0);
    });
  });
}
