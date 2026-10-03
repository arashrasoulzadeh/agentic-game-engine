import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SceneTransition', () {
    late World world;

    setUp(() {
      world = World(width: 800, height: 600);
      registerCoreComponents(world);
      registerFlutterComponents(world);
    });

    test('fade covering phase animates alpha from 0 to 255 then cleans up', () {
      final entity = world.spawn();
      final transition = SceneTransition(
        config: const SceneTransitionConfig(type: SceneTransitionType.fade, duration: 0.5),
        covering: true,
      );
      world.storeOf<SceneTransition>().set(entity, transition);
      transition.start(world);

      final tintStore = world.storeOf<ScreenTint>();
      expect(tintStore.length, 1);
      expect(tintStore.denseAt(0).colorArgb >>> 24, 0);

      transition.update(0.25, world);
      final midAlpha = tintStore.denseAt(0).colorArgb >>> 24;
      expect(midAlpha, greaterThan(0));
      expect(midAlpha, lessThan(255));

      final complete = transition.update(0.25, world);

      expect(complete, isTrue);
      expect(transition.isRunning, isFalse);
      // The ScreenTint entity it created is torn down once the phase
      // finishes -- a stuck fully-opaque or half-faded tint would
      // otherwise linger over whichever scene loads next.
      expect(tintStore.length, 0);
    });

    test('fade revealing phase animates alpha from 255 down to 0', () {
      final entity = world.spawn();
      final transition = SceneTransition(
        config: const SceneTransitionConfig(type: SceneTransitionType.fade, duration: 0.5),
        covering: false,
      );
      world.storeOf<SceneTransition>().set(entity, transition);
      transition.start(world);

      final tintStore = world.storeOf<ScreenTint>();
      expect(tintStore.denseAt(0).colorArgb >>> 24, 255);

      transition.update(0.5, world);

      expect(tintStore.length, 0);
    });

    test('iris covering phase shrinks the reveal radius to 0', () {
      final entity = world.spawn();
      final transition = SceneTransition(
        config: const SceneTransitionConfig(type: SceneTransitionType.iris, duration: 0.5),
        covering: true,
      );
      world.storeOf<SceneTransition>().set(entity, transition);
      transition.start(world);

      final clipStore = world.storeOf<ClipShape>();
      expect(clipStore.length, 1);
      final startRadius = clipStore.denseAt(0).radius;
      expect(startRadius, greaterThan(0));

      transition.update(0.25, world);
      final midRadius = clipStore.denseAt(0).radius;
      expect(midRadius, lessThan(startRadius));

      transition.update(0.25, world);

      // Fully covered means fully clipped away -- the entity is torn
      // down, not left sitting at radius 0.
      expect(clipStore.length, 0);
    });

    test('iris revealing phase grows the reveal radius from 0', () {
      final entity = world.spawn();
      final transition = SceneTransition(
        config: const SceneTransitionConfig(type: SceneTransitionType.iris, duration: 0.5),
        covering: false,
      );
      world.storeOf<SceneTransition>().set(entity, transition);
      transition.start(world);

      final clipStore = world.storeOf<ClipShape>();
      expect(clipStore.denseAt(0).radius, 0);

      transition.update(0.5, world);

      expect(clipStore.length, 0);
    });

    test('SceneTransitionSystem only advances running transitions', () {
      final entity = world.spawn();
      final transition = SceneTransition(
        config: const SceneTransitionConfig(type: SceneTransitionType.fade, duration: 1),
        covering: true,
      );
      world.storeOf<SceneTransition>().set(entity, transition);
      // Not started -- isRunning is still false, so the system must
      // leave it alone instead of crashing on a null tween.
      final system = SceneTransitionSystem();
      expect(() => system.update(world, 0.1), returnsNormally);
      expect(transition.progress, 0.0);

      transition.start(world);
      system.update(world, 0.5);
      expect(transition.progress, greaterThan(0));
    });

    test('SceneTransitionConfig round-trips through toJson/fromJson', () {
      const config = SceneTransitionConfig(
        type: SceneTransitionType.iris,
        duration: 0.75,
        easing: EasingType.easeOutQuad,
        fadeColorArgb: 0xFF112233,
      );
      final restored = SceneTransitionConfig.fromJson(config.toJson());

      expect(restored.type, config.type);
      expect(restored.duration, config.duration);
      expect(restored.easing, config.easing);
      expect(restored.fadeColorArgb, config.fadeColorArgb);
    });

    test('SceneTransition component is registered and round-trips via World.toJson', () {
      final entity = world.spawn();
      final transition = SceneTransition(
        config: const SceneTransitionConfig(),
        covering: true,
      );
      transition.start(world);
      world.storeOf<SceneTransition>().set(entity, transition);

      final json = world.toJson();
      final restored = World(width: 800, height: 600);
      registerCoreComponents(restored);
      registerFlutterComponents(restored);
      // applyPatch only writes components onto entities that already
      // exist in the target World -- it's a patch mechanism, not a
      // "recreate the world from scratch" one -- so spawn matching
      // entities first.
      restored.spawn();
      restored.applyPatch(json);

      final restoredTransition = restored.storeOf<SceneTransition>().denseAt(0);
      expect(restoredTransition.covering, isTrue);
      expect(restoredTransition.isRunning, isTrue);
    });
  });
}
