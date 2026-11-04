
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart';

void main() {
  const view = Size(200, 100);

  group('dead-zone', () {
    test('the camera holds still while the target stays inside the window', () {
      final cam = Camera(x: 100, y: 50);
      final rig = CameraRig(deadZoneWidth: 40, deadZoneHeight: 20);
      rig.update(cam, targetX: 115, targetY: 56, dt: 0.016, viewportSize: view);
      expect((cam.x, cam.y), (100, 50));
    });

    test('it moves just far enough to keep the target at the window edge', () {
      final cam = Camera(x: 100, y: 50);
      final rig = CameraRig(deadZoneWidth: 40, deadZoneHeight: 20);
      rig.update(cam, targetX: 150, targetY: 30, dt: 0.016, viewportSize: view);
      expect(cam.x, closeTo(130, 1e-9)); // target at +20 from the camera
      expect(cam.y, closeTo(40, 1e-9)); // target at -10
    });

    test('no dead-zone centres on the target', () {
      final cam = Camera(x: 0, y: 0);
      CameraRig().update(
        cam,
        targetX: 70,
        targetY: 40,
        dt: 0.016,
        viewportSize: view,
      );
      expect((cam.x, cam.y), (70, 40));
    });
  });

  group('look-ahead', () {
    test('leads in the direction of travel, up to the configured distance', () {
      final cam = Camera();
      final rig = CameraRig(
        lookAhead: 30,
        lookAheadSpeed: 100,
        lookAheadHalfLife: 0,
      );
      rig.update(
        cam,
        targetX: 0,
        targetY: 0,
        velocityX: 200,
        dt: 0.016,
        viewportSize: view,
      );
      expect(cam.x, closeTo(30, 1e-9)); // fast: the full distance
      rig.update(
        cam,
        targetX: 0,
        targetY: 0,
        velocityX: 50,
        dt: 0.016,
        viewportSize: view,
      );
      expect(cam.x, closeTo(15, 1e-9)); // half speed: half the lead
      rig.update(
        cam,
        targetX: 0,
        targetY: 0,
        velocityX: -200,
        dt: 0.016,
        viewportSize: view,
      );
      expect(cam.x, closeTo(-30, 1e-9));
    });

    test('is eased: reversing does not snap the camera', () {
      final cam = Camera();
      final rig = CameraRig(
        lookAhead: 40,
        lookAheadSpeed: 10,
        lookAheadHalfLife: 0.5,
      );
      for (var i = 0; i < 200; i++) {
        rig.update(
          cam,
          targetX: 0,
          targetY: 0,
          velocityX: 100,
          dt: 0.016,
          viewportSize: view,
        );
      }
      expect(rig.lookOffset.$1, closeTo(40, 1));
      rig.update(
        cam,
        targetX: 0,
        targetY: 0,
        velocityX: -100,
        dt: 0.016,
        viewportSize: view,
      );
      expect(
        rig.lookOffset.$1,
        greaterThan(30),
      ); // one frame later, barely moved
    });

    test('standing still lets the lead relax back to the target', () {
      final cam = Camera();
      final rig = CameraRig(
        lookAhead: 40,
        lookAheadSpeed: 10,
        lookAheadHalfLife: 0.1,
      );
      for (var i = 0; i < 100; i++) {
        rig.update(
          cam,
          targetX: 0,
          targetY: 0,
          velocityX: 100,
          dt: 0.016,
          viewportSize: view,
        );
      }
      for (var i = 0; i < 200; i++) {
        rig.update(cam, targetX: 0, targetY: 0, dt: 0.016, viewportSize: view);
      }
      expect(rig.lookOffset.$1.abs(), lessThan(0.5));
    });
  });

  group('bounds', () {
    test('the viewport never shows past the level rectangle', () {
      final cam = Camera();
      final rig = CameraRig(bounds: const Rect.fromLTWH(0, 0, 600, 300));
      rig.update(
        cam,
        targetX: -50,
        targetY: -50,
        dt: 0.016,
        viewportSize: view,
      );
      expect((cam.x, cam.y), (100, 50)); // half the viewport from the corner
      rig.update(
        cam,
        targetX: 900,
        targetY: 900,
        dt: 0.016,
        viewportSize: view,
      );
      expect((cam.x, cam.y), (500, 250));
    });

    test('a level smaller than the viewport is centred', () {
      final cam = Camera();
      final rig = CameraRig(bounds: const Rect.fromLTWH(0, 0, 100, 40));
      rig.update(cam, targetX: 10, targetY: 10, dt: 0.016, viewportSize: view);
      expect((cam.x, cam.y), (50, 20));
    });

    test('bounds account for zoom', () {
      final cam = Camera(zoom: 2);
      final rig = CameraRig(bounds: const Rect.fromLTWH(0, 0, 600, 300));
      rig.update(
        cam,
        targetX: -50,
        targetY: -50,
        dt: 0.016,
        viewportSize: view,
      );
      expect((cam.x, cam.y), (50, 25)); // viewport is 100x50 world units
    });

    test('defaultBounds apply only when no bounds are set', () {
      final cam = Camera();
      CameraRig().update(
        cam,
        targetX: -50,
        targetY: -50,
        dt: 0.016,
        viewportSize: view,
        defaultBounds: const Rect.fromLTWH(0, 0, 600, 300),
      );
      expect((cam.x, cam.y), (100, 50));
      CameraRig(bounds: const Rect.fromLTWH(0, 0, 1000, 1000)).update(
        cam,
        targetX: -50,
        targetY: -50,
        dt: 0.016,
        viewportSize: view,
        defaultBounds: const Rect.fromLTWH(0, 0, 600, 300),
      );
      expect((cam.x, cam.y), (100, 50)); // its own bounds, same corner rule
    });
  });

  test('easing: the camera covers part of the way each frame', () {
    final cam = Camera();
    final rig = CameraRig(halfLife: 0.1);
    rig.update(cam, targetX: 100, targetY: 0, dt: 0.1, viewportSize: view);
    expect(cam.x, closeTo(50, 1e-9)); // half the distance in one half-life
  });

  test('reset snaps to the target and forgets the lead', () {
    final cam = Camera();
    final rig = CameraRig(
      lookAhead: 40,
      lookAheadSpeed: 10,
      lookAheadHalfLife: 0,
    );
    rig.update(
      cam,
      targetX: 0,
      targetY: 0,
      velocityX: 100,
      dt: 0.016,
      viewportSize: view,
    );
    rig.reset(cam, 300, 200);
    expect((cam.x, cam.y, rig.lookOffset), (300, 200, (0.0, 0.0)));
  });

  testWidgets(
    'EngineView drives the camera through a rig: lead and world bounds',
    (tester) async {
      final world = World(width: 600, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      final hero = world.spawn();
      world.componentsOf<Position>().set(hero, Position(300, 150));
      world.componentsOf<Velocity>().set(hero, Velocity(300, 0));
      final camera = Camera();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: EngineView(
                world: world,
                atlasRegistry: AtlasRegistry(),
                camera: camera,
                cameraFollowEntity: hero,
                cameraRig: CameraRig(
                  lookAhead: 25,
                  lookAheadSpeed: 100,
                  lookAheadHalfLife: 0,
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(camera.x, closeTo(325, 1e-6)); // 300 + the 25 unit lead
      expect(camera.y, closeTo(150, 1e-6));
      // Move the hero to the corner: the world rectangle clamps the camera.
      world.componentsOf<Position>().get(hero)!
        ..x = 590
        ..y = 5;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(camera.x, closeTo(500, 1e-6)); // 600 - half the 200 wide view
      expect(camera.y, closeTo(50, 1e-6));
    },
  );
}
