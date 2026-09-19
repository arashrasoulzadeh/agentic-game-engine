import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveSolidCircleAabb', () {
    test('pushes out to the left when overlapping from the left side', () {
      final pos = Position(18, 50);
      final vel = Velocity(10, 0);

      final side = resolveSolidCircleAabb(
        pos: pos,
        vel: vel,
        radius: 5,
        left: 20,
        right: 100,
        top: 0,
        bottom: 200,
      );

      expect(side, CollisionSide.left);
      expect(pos.x, 20 - 5);
      expect(vel.x, 0);
    });

    test('pushes out to the right when overlapping from the right side', () {
      final pos = Position(102, 50);
      final vel = Velocity(-10, 0);

      final side = resolveSolidCircleAabb(
        pos: pos,
        vel: vel,
        radius: 5,
        left: 0,
        right: 100,
        top: 0,
        bottom: 200,
      );

      expect(side, CollisionSide.right);
      expect(pos.x, 100 + 5);
      expect(vel.x, 0);
    });

    test('pushes out to the top when landing on top', () {
      final pos = Position(50, 8);
      final vel = Velocity(0, 10);

      final side = resolveSolidCircleAabb(
        pos: pos,
        vel: vel,
        radius: 5,
        left: 0,
        right: 100,
        top: 10,
        bottom: 200,
      );

      expect(side, CollisionSide.top);
      expect(pos.y, 10 - 5);
      expect(vel.y, 0);
    });

    test('pushes out to the bottom when overlapping from below', () {
      final pos = Position(50, 202);
      final vel = Velocity(0, -10);

      final side = resolveSolidCircleAabb(
        pos: pos,
        vel: vel,
        radius: 5,
        left: 0,
        right: 100,
        top: 0,
        bottom: 200,
      );

      expect(side, CollisionSide.bottom);
      expect(pos.y, 200 + 5);
      expect(vel.y, 0);
    });

    test('no overlap is a no-op and returns none', () {
      final pos = Position(0, 0);
      final vel = Velocity(0, 0);

      final side = resolveSolidCircleAabb(
        pos: pos,
        vel: vel,
        radius: 1,
        left: 100,
        right: 200,
        top: 100,
        bottom: 200,
      );

      expect(side, CollisionSide.none);
      expect(pos.x, 0);
      expect(pos.y, 0);
    });

    test(
        'an entity resting exactly at the top boundary (distSq == radius*radius) '
        'keeps resolving as top, every call, not just the one that landed it '
        '(regression: grounded used to flicker false every other tick at rest)',
        tags: ['regression'], () {
      // Exactly the position resolveSolidCircleAabb itself snaps an
      // entity to the instant it lands: pos.y == top - radius, i.e.
      // sitting precisely on the boundary rather than overlapping it.
      final pos = Position(50, 100 - 5);
      final vel = Velocity(0, 0);

      for (var i = 0; i < 5; i++) {
        final side = resolveSolidCircleAabb(
          pos: pos,
          vel: vel,
          radius: 5,
          left: 0,
          right: 100,
          top: 100,
          bottom: 200,
        );
        expect(side, CollisionSide.top, reason: 'call #$i');
        expect(pos.y, 95);
        expect(vel.y, 0);
      }
    });
  });
}
