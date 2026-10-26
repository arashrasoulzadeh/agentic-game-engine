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

  test('plays mapped id when AnimationSystem enters an sfx frame', () {
    final world = buildWorld();
    final plays = <(String, double)>[];
    final sfx = AnimationSfxSystem.custom(
      soundIds: {'swing': 'sfx/sword.wav'},
      playSound: (path, {double volume = 1.0}) async {
        plays.add((path, volume));
      },
    );
    sfx.attach(world);
    world.addSystem(sfx);

    final id = world.spawn();
    world.storeOf<Sprite>().set(id, Sprite('atlas', 'frame0'));
    world.storeOf<AnimationState>().set(
      id,
      AnimationState(
        AnimationClip(
          'attack',
          ['frame0', 'frame1'],
          frameDurationSeconds: 0.1,
          loop: false,
          frameEvents: [
            [],
            [
              const AnimationEvent('sfx', {'id': 'swing', 'volume': 0.5}),
              const AnimationEvent('hitbox_on'),
            ],
          ],
        ),
      ),
    );

    world.step(0.1);
    expect(plays, [('sfx/sword.wav', 0.5)]);
  });

  test('uses asset path directly when data.asset is set', () {
    final world = buildWorld();
    final plays = <String>[];
    final sfx = AnimationSfxSystem.custom(
      playSound: (path, {double volume = 1.0}) async {
        plays.add(path);
      },
    );
    sfx.attach(world);

    final id = world.spawn();
    world.storeOf<Sprite>().set(id, Sprite('atlas', 'frame0'));
    world.storeOf<AnimationState>().set(
      id,
      AnimationState(
        AnimationClip(
          'hit',
          ['frame0', 'frame1'],
          frameDurationSeconds: 0.1,
          loop: false,
          frameEvents: [
            [],
            [
              const AnimationEvent('sfx', {'asset': 'sfx/impact.wav'}),
            ],
          ],
        ),
      ),
    );

    world.step(0.1);
    expect(plays, ['sfx/impact.wav']);
  });

  test('positional uses entity Position and listenerAt', () {
    final world = buildWorld();
    final positional = <Map<String, double>>[];
    final sfx = AnimationSfxSystem.custom(
      positional: true,
      listenerAt: (_) => (0.0, 0.0),
      playSound: (path, {double volume = 1.0}) async {},
      playPositional:
          (
            path, {
            required double sourceX,
            required double sourceY,
            required double listenerX,
            required double listenerY,
            double maxDistance = 800,
            double volume = 1.0,
          }) async {
            positional.add({
              'sx': sourceX,
              'sy': sourceY,
              'lx': listenerX,
              'ly': listenerY,
              'vol': volume,
            });
          },
    );
    sfx.attach(world);

    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(40, 10));
    world.storeOf<Sprite>().set(id, Sprite('atlas', 'frame0'));
    world.storeOf<AnimationState>().set(
      id,
      AnimationState(
        AnimationClip(
          'step',
          ['frame0', 'frame1'],
          frameDurationSeconds: 0.1,
          loop: false,
          frameEvents: [
            [],
            [const AnimationEvent('sfx', {'id': 'foot.wav'})],
          ],
        ),
      ),
    );

    world.step(0.1);
    expect(positional, hasLength(1));
    expect(positional.single['sx'], 40);
    expect(positional.single['sy'], 10);
    expect(positional.single['lx'], 0);
    expect(positional.single['ly'], 0);
  });

  test('ignores non-sfx frame events', () {
    final world = buildWorld();
    var plays = 0;
    final sfx = AnimationSfxSystem.custom(
      playSound: (path, {double volume = 1.0}) async {
        plays++;
      },
    );
    sfx.attach(world);

    final id = world.spawn();
    world.storeOf<Sprite>().set(id, Sprite('atlas', 'frame0'));
    world.storeOf<AnimationState>().set(
      id,
      AnimationState(
        AnimationClip(
          'attack',
          ['frame0', 'frame1'],
          frameDurationSeconds: 0.1,
          loop: false,
          frameEvents: [
            [],
            [const AnimationEvent('hitbox_on')],
          ],
        ),
      ),
    );

    world.step(0.1);
    expect(plays, 0);
  });
}
