import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_flutter/src/rendering/debug_memory_stub.dart' as web_memory;
import 'package:flutter_test/flutter_test.dart';

class EmptyScene extends Scene {
  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {}
}

class EmptyGame extends Game {
  @override
  GameConfig get config => const GameConfig(worldWidth: 100, worldHeight: 100);
  @override
  Scene createInitialScene() => EmptyScene();
}

World buildWorld() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  return world;
}

void main() {
  test('rendering components round-trip through the world registry', () {
    final world = buildWorld();
    final id = world.spawn();
    world.storeOf<Text>().set(id, Text('hello'));
    world.storeOf<HudBar>().set(id, HudBar(value: 4, maxValue: 9));
    world.storeOf<NineSliceSprite>().set(id, NineSliceSprite('ui', 'panel',
      width: 80, height: 60, insetLeft: 2, insetTop: 3, insetRight: 4, insetBottom: 5));
    world.storeOf<AnimationTransition>().set(id, AnimationTransition('hero', 'idle',
      remainingSeconds: 0.5, totalSeconds: 1));
    world.storeOf<Light2D>().set(id, Light2D(radius: 40));
    world.storeOf<ScreenTint>().set(id, ScreenTint(0x880000FF));
    world.storeOf<ClipShape>().set(id, ClipShape(radius: 25));
    final data = world.components.serializeEntity(id);
    final copy = world.spawn();
    world.components.applyToEntity(copy, data);
    expect(world.components.serializeEntity(copy), data);
    expect(data.keys, containsAll(['text', 'hudBar', 'nineSliceSprite',
      'animationTransition', 'light2d', 'screenTint', 'clipShape']));
  });

  test('animation transitions expire together without skipping dense-store entries', () {
    final world = buildWorld();
    final system = AnimationTransitionSystem();
    expect(system.name, 'animationTransition');
    final store = world.storeOf<AnimationTransition>();
    final ids = List.generate(3, (_) => world.spawn());
    for (var i = 0; i < ids.length; i++) {
      store.set(ids[i], AnimationTransition('hero', 'idle',
        remainingSeconds: i == 2 ? 1 : 0.2, totalSeconds: 1));
    }
    system.update(world, 0.3);
    expect(store.has(ids[0]), isFalse);
    expect(store.has(ids[1]), isFalse);
    expect(store.get(ids[2])!.remainingSeconds, closeTo(0.7, 1e-9));
    system.update(world, 1);
    expect(store.length, 0);
    expect(LightFlickerSystem().name, 'lightFlicker');
  });

  test('unattached scene controllers report lifecycle errors', () {
    final controller = SceneController();
    final scene = EmptyScene();
    expect(() => controller.loadScene(scene), throwsStateError);
    expect(() => controller.pushOverlay(scene), throwsStateError);
    expect(controller.popOverlay, throwsStateError);
    var loaded = false, pushed = false, popped = false;
    controller.attach(loadScene: (s) => loaded = identical(s, scene),
      pushOverlay: (s) => pushed = identical(s, scene), popOverlay: () => popped = true);
    controller.loadScene(scene);
    controller.pushOverlay(scene);
    controller.popOverlay();
    expect([loaded, pushed, popped], everyElement(isTrue));
    final world = buildWorld();
    scene.handleTap(world, controller, Offset.zero);
    expect(world.entities.count, 0);
    expect(EmptyGame().cameraFollowEntity(world), isNull);
    expect(web_memory.currentMemoryUsageBytes(), isNull);
  });

  test('save version errors include both versions and migration guidance', () {
    final message = SaveVersionException(1, 3).toString();
    expect(message, contains('schema version 1'));
    expect(message, contains('version 3'));
    expect(message, contains('migrate'));
    final spec = SaveSlotSpec(slot: 'slot1', label: 'First slot');
    expect(spec.slot, 'slot1');
    expect(spec.label, 'First slot');
  });

  test('skipping a camera shake does not hold up a cinematic', () {
    final world = buildWorld();
    final cinematic = CinematicSystem([
      CameraShakeStep(Camera(), magnitude: 3, duration: 1),
    ]);
    cinematic.skip(world);
    expect(cinematic.isPlaying, isFalse);
  });
}
