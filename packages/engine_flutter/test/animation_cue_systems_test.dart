import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  World buildWorld() {
    final world = World(width: 200, height: 100);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    world.addSystem(AnimationSystem());
    return world;
  }

  test('AnimationShakeSystem shakes the camera on shake cues', () {
    final world = buildWorld();
    final camera = Camera(x: 0, y: 0);
    final shake = AnimationShakeSystem(camera)..attach(world);

    final id = world.spawn();
    world.storeOf<Sprite>().set(id, Sprite('atlas', 'f0'));
    world.storeOf<AnimationState>().set(
      id,
      AnimationState(
        AnimationClip(
          'land',
          ['f0', 'f1'],
          frameDurationSeconds: 0.1,
          loop: false,
          frameEvents: [
            [],
            [
              const AnimationEvent('shake', {
                'magnitude': 5,
                'duration': 0.2,
                'impulse': true,
              }),
            ],
          ],
        ),
      ),
    );

    world.step(0.1);
    camera.update(0); // apply shake bookkeeping
    expect(camera.shakeOffset.dx != 0 || camera.shakeOffset.dy != 0, isTrue);
    expect(shake.name, 'animationShake');
  });

  test('AnimationParticleSystem bumps burstCount on particle cues', () {
    final world = buildWorld();
    AnimationParticleSystem().attach(world);

    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(10, 20));
    world.storeOf<Sprite>().set(id, Sprite('atlas', 'f0'));
    world.storeOf<ParticleEmitter>().set(id, ParticleEmitter());
    world.storeOf<AnimationState>().set(
      id,
      AnimationState(
        AnimationClip(
          'step',
          ['f0', 'f1'],
          frameDurationSeconds: 0.1,
          loop: false,
          frameEvents: [
            [],
            [const AnimationEvent('particle', {'count': 12})],
          ],
        ),
      ),
    );

    world.step(0.1);
    expect(world.storeOf<ParticleEmitter>().get(id)!.burstCount, 12);
  });

  test('DialogueSfxSystem plays mapped keys from DialoguePlaySoundEvent', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final plays = <String>[];
    DialogueSfxSystem.custom(
      soundIds: {'click': 'ui/click.wav'},
      playSound: (path, {double volume = 1.0}) async {
        plays.add(path);
      },
    ).attach(world);

    world.events.emit(DialoguePlaySoundEvent('click'));
    world.events.emit(DialoguePlaySoundEvent('vo/line.wav'));
    world.events.flush();

    expect(plays, ['ui/click.wav', 'vo/line.wav']);
  });
}
