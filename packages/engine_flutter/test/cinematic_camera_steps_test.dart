import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 1000, height: 1000);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  return world;
}

void main() {
  group('ScreenTint', () {
    test('round-trips through toJson/fromJson', () {
      final tint = ScreenTint(0x80FF0000);
      final restored = ScreenTint.fromJson(tint.toJson());
      expect(restored.colorArgb, 0x80FF0000);
    });
  });

  group('CameraPanStep', () {
    test('pans camera.x/.y from its current position to the target over duration', () {
      final world = _buildWorld();
      final camera = Camera(x: 0, y: 0);
      final step = CameraPanStep(camera, toX: 100, toY: 200, duration: 2);

      step.start(world);
      final done1 = step.update(world, 1); // halfway
      expect(done1, isFalse);
      expect(camera.x, 50);
      expect(camera.y, 100);

      final done2 = step.update(world, 1); // fully elapsed
      expect(done2, isTrue);
      expect(camera.x, 100);
      expect(camera.y, 200);
    });

    test('captures the from position at start(), so a chained pan starts from '
        'wherever the camera actually is, not (0, 0)', () {
      final world = _buildWorld();
      final camera = Camera(x: 500, y: 300);
      final step = CameraPanStep(camera, toX: 600, toY: 300, duration: 1);

      step.start(world);
      step.update(world, 0); // t=0, should read back the captured start position

      expect(camera.x, 500);
    });

    test('skip jumps straight to the target without needing start() first', () {
      final world = _buildWorld();
      final camera = Camera(x: 0, y: 0);
      final step = CameraPanStep(camera, toX: 50, toY: 75, duration: 5);

      step.skip(world);

      expect(camera.x, 50);
      expect(camera.y, 75);
    });
  });

  group('CameraZoomStep', () {
    test('animates camera.zoom from its current value to the target over duration', () {
      final world = _buildWorld();
      final camera = Camera(zoom: 1);
      final step = CameraZoomStep(camera, toZoom: 3, duration: 2);

      step.start(world);
      step.update(world, 1);
      expect(camera.zoom, 2);

      final done = step.update(world, 1);
      expect(done, isTrue);
      expect(camera.zoom, 3);
    });

    test('skip jumps straight to the target zoom', () {
      final world = _buildWorld();
      final camera = Camera(zoom: 1);
      CameraZoomStep(camera, toZoom: 5, duration: 10).skip(world);
      expect(camera.zoom, 5);
    });
  });

  group('CameraShakeStep', () {
    test('triggers Camera.shake once on start and holds the sequence for the '
        'full duration', () {
      final world = _buildWorld();
      final camera = Camera();
      final step = CameraShakeStep(camera, magnitude: 10, duration: 0.5);

      step.start(world);
      camera.update(0.1); // let the shake actually produce an offset
      final screen = camera.worldToScreen(0, 0, const Size(100, 100));
      // Some nonzero jitter should be present (extremely unlikely to
      // land on exactly (50, 50) by chance with magnitude 10).
      expect(screen, isNot(const Offset(50, 50)));

      expect(step.update(world, 0.3), isFalse, reason: 'duration not elapsed yet');
      expect(step.update(world, 0.3), isTrue, reason: 'duration now elapsed');
    });
  });

  group('CameraFollowStep', () {
    test('hard-snaps to the target entity\'s Position every tick when smoothing '
        'is 1.0 (default)', () {
      final world = _buildWorld();
      final camera = Camera(x: 0, y: 0);
      final target = world.spawn();
      world.storeOf<Position>().set(target, Position(300, 400));

      final step = CameraFollowStep(camera, target, duration: 1);
      final done = step.update(world, 0.5);

      expect(done, isFalse);
      expect(camera.x, 300);
      expect(camera.y, 400);
    });

    test('lower smoothing trails behind the target instead of snapping', () {
      final world = _buildWorld();
      final camera = Camera(x: 0, y: 0);
      final target = world.spawn();
      world.storeOf<Position>().set(target, Position(100, 0));

      final step = CameraFollowStep(camera, target, duration: 5, smoothing: 0.1);
      step.update(world, 0.1);

      expect(camera.x, 10); // 0 + (100 - 0) * 0.1
      expect(camera.x, lessThan(100));
    });

    test('completes once duration elapses, regardless of smoothing', () {
      final world = _buildWorld();
      final camera = Camera();
      final target = world.spawn();
      world.storeOf<Position>().set(target, Position(0, 0));

      final step = CameraFollowStep(camera, target, duration: 1);
      expect(step.update(world, 0.6), isFalse);
      expect(step.update(world, 0.6), isTrue);
    });

    test('skip snaps directly to the target position', () {
      final world = _buildWorld();
      final camera = Camera(x: 0, y: 0);
      final target = world.spawn();
      world.storeOf<Position>().set(target, Position(42, 84));

      CameraFollowStep(camera, target, duration: 1).skip(world);

      expect(camera.x, 42);
      expect(camera.y, 84);
    });
  });

  group('ScreenTintStep', () {
    test('spawns a ScreenTint entity on start and fades its alpha over duration', () {
      final world = _buildWorld();
      final step = ScreenTintStep(
        colorArgb: 0x00FF0000, // red; alpha portion ignored, fromAlpha/toAlpha drive it
        fromAlpha: 0,
        toAlpha: 1,
        duration: 2,
      );

      step.start(world);
      final tints = world.storeOf<ScreenTint>();
      expect(tints.length, 1);
      expect(Color(tints.denseAt(0).colorArgb).a, 0);

      step.update(world, 1); // halfway
      expect(Color(tints.denseAt(0).colorArgb).a, closeTo(0.5, 0.01));
      // Hue preserved throughout.
      expect(tints.denseAt(0).colorArgb & 0x00FFFFFF, 0x00FF0000 & 0x00FFFFFF);

      final done = step.update(world, 1);
      expect(done, isTrue);
      expect(Color(tints.denseAt(0).colorArgb).a, closeTo(1.0, 0.01));
    });

    test('skip spawns the entity (if start() never ran) and jumps to toAlpha', () {
      final world = _buildWorld();
      final step = ScreenTintStep(
        colorArgb: 0xFF000000,
        fromAlpha: 0,
        toAlpha: 0.8,
        duration: 3,
      );

      step.skip(world);

      final tints = world.storeOf<ScreenTint>();
      expect(tints.length, 1);
      expect(Color(tints.denseAt(0).colorArgb).a, closeTo(0.8, 0.01));
    });

    test('two independent steps (no shared entity) spawn two separate entities '
        '-- the first is left stuck at its own toAlpha once the second one '
        'starts animating a different entity entirely', () {
      final world = _buildWorld();
      final up = ScreenTintStep(colorArgb: 0xFFFF0000, fromAlpha: 0, toAlpha: 0.5, duration: 1);
      final down = ScreenTintStep(colorArgb: 0xFFFF0000, fromAlpha: 0.5, toAlpha: 0, duration: 1);

      up.start(world);
      up.update(world, 1); // completes at alpha 0.5
      down.start(world);
      down.update(world, 1); // completes at alpha 0 -- but on its OWN entity

      expect(world.storeOf<ScreenTint>().length, 2);
      expect(Color(world.storeOf<ScreenTint>().get(up.entity!)!.colorArgb).a, closeTo(0.5, 0.01),
          reason: "the first step's entity is never touched again -- stuck at 0.5");
      expect(Color(world.storeOf<ScreenTint>().get(down.entity!)!.colorArgb).a, closeTo(0, 0.01));
    });

    test('a flash (up then down) sharing one entity via the entity parameter '
        'correctly resets back to 0 -- the fix for the bug above', () {
      final world = _buildWorld();
      final flashEntity = world.spawn();
      final up = ScreenTintStep(
        colorArgb: 0xFFFF0000,
        fromAlpha: 0,
        toAlpha: 0.5,
        duration: 1,
        entity: flashEntity,
      );
      final down = ScreenTintStep(
        colorArgb: 0xFFFF0000,
        fromAlpha: 0.5,
        toAlpha: 0,
        duration: 1,
        entity: flashEntity,
      );

      up.start(world);
      up.update(world, 1);
      down.start(world);
      down.update(world, 1);

      expect(world.storeOf<ScreenTint>().length, 1, reason: 'one shared entity, not two');
      expect(
        Color(world.storeOf<ScreenTint>().get(flashEntity)!.colorArgb).a,
        closeTo(0, 0.01),
      );
    });
  });
}
