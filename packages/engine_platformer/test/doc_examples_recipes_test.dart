// The platformer recipes under docs/examples/ (custom-behavior, health-bar,
// spawn-enemy-with-patrol-ai) and the code blocks of docs/concepts/platformer.md,
// executed so they cannot drift from the API.
import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

class FleeWhenHurtBehavior implements Behavior {
  FleeWhenHurtBehavior({
    required this.fleeToX,
    this.healthThreshold = 0.3,
    this.speed = 100,
  });

  final double fleeToX;
  final double healthThreshold;
  final double speed;

  @override
  Action decide(WorldView view, EntityId self) {
    final health = view.component<Health>(self);
    final pos = view.component<Position>(self);
    if (health == null || pos == null) return const NoOpAction();

    if (health.current / health.max > healthThreshold) {
      return const NoOpAction();
    }

    final direction = fleeToX > pos.x ? 1.0 : -1.0;
    return SetVelocityAction(self, direction * speed, 0);
  }
}

void main() {
  late World world;

  setUp(() {
    world = World(width: 800, height: 600);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    registerPlatformerComponents(world);
  });

  group('custom-behavior recipe', () {
    test('a hurt boss flees; a healthy one does nothing', () {
      final behaviors = BehaviorRegistry();
      behaviors.register('flee-when-hurt', FleeWhenHurtBehavior(fleeToX: 50));
      world.addSystem(AISystem(behaviors));

      final bossId = world.spawn();
      world.storeOf<Position>().set(bossId, Position(300, 0));
      world.storeOf<Velocity>().set(bossId, Velocity(0, 0));
      world.storeOf<Health>().set(bossId, Health(current: 100, max: 100));
      world.storeOf<AIState>().set(bossId, AIState('flee-when-hurt'));

      world.step(1 / 60);
      expect(world.storeOf<Velocity>().get(bossId)!.x, 0, reason: 'healthy');

      world.storeOf<Health>().get(bossId)!.current = 20;
      world.step(1 / 60);
      expect(
        world.storeOf<Velocity>().get(bossId)!.x,
        -100,
        reason: 'flees toward x = 50 (to the left)',
      );
    });

    test('memory on AIState carries a countdown between decisions', () {
      final world2 = World(width: 10, height: 10);
      registerCoreComponents(world2);
      final e = world2.spawn();
      world2.storeOf<AIState>().set(e, AIState('count'));
      final b = _Countdown();
      for (var i = 0; i < 3; i++) {
        b.decide(WorldView(world2), e);
      }
      expect(world2.storeOf<AIState>().get(e)!.memory['ticksLeft'], 57);
    });
  });

  group('health-bar recipe', () {
    test('a HUD bar follows the player\'s health', () {
      final input = InputController().state;
      final player = spawnPlayer(
        world,
        x: 0,
        y: 0,
        input: input,
        maxHealth: 100,
      );

      final bar = spawnHealthHudBar(
        world,
        source: player,
        x: 20,
        y: 20,
        width: 200,
        height: 20,
        fillColorArgb: 0xFFE0304C,
        backgroundColorArgb: 0x80000000,
      );
      expect(world.entities.isAlive(bar), isTrue);
      expect(world.storeOf<Health>().get(player)!.max, 100);
    });

    test(
      'a world-space bar over an enemy is repositioned by hand each tick',
      () {
        final enemy = spawnEnemy(
          world,
          x: 100,
          y: 300,
          behaviorId: 'x',
          maxHealth: 10,
        );
        final enemyBar = spawnHealthHudBar(
          world,
          source: enemy,
          x: 100,
          y: 280,
          width: 40,
          height: 6,
          screenSpace: false,
        );
        world.storeOf<Position>().get(enemy)!.x = 150;
        world.storeOf<Position>().set(
          enemyBar,
          Position(
            world.storeOf<Position>().get(enemy)!.x,
            world.storeOf<Position>().get(enemy)!.y - 20,
          ),
        );
        expect(world.storeOf<Position>().get(enemyBar)!.x, 150);
      },
    );
  });

  group('spawn-enemy-with-patrol-ai recipe', () {
    test(
      'a patrolling guard moves within its range once the AI system runs',
      () {
        final behaviors = BehaviorRegistry();
        behaviors.register(
          'guard-patrol',
          PatrolBehavior(minX: 200, maxX: 400, speed: 50, avoidLedges: true),
        );

        final guard = spawnEnemy(
          world,
          x: 300,
          y: 300,
          behaviorId: 'guard-patrol',
          affectedByGravity: true,
          maxHealth: 30,
          atlasId: 'characters',
          spriteRegion: 'guard_idle',
        );
        world.addSystem(AISystem(behaviors));

        expect(world.storeOf<Gravity>().has(guard), isTrue);
        expect(world.storeOf<PlatformerController>().has(guard), isTrue);
        expect(world.storeOf<Health>().get(guard)!.max, 30);

        world.step(1 / 60);
        expect(world.storeOf<Velocity>().get(guard)!.x.abs(), 50);
      },
    );

    test('FollowBehavior registers like any other behavior', () {
      final behaviors = BehaviorRegistry();
      final player = world.spawn();
      behaviors.register(
        'chase',
        FollowBehavior(target: player, speed: 80, maxDistance: 250),
      );
      expect(behaviors.has('chase'), isTrue);
    });
  });

  group('animation-events recipe', () {
    test('frameEvents drive sfx / shake / particle / gated melee bridges', () {
      final plays = <String>[];
      final camera = Camera();
      world.addSystem(AnimationSystem());
      world.addSystem(AttackSystem());
      AnimationSfxSystem.custom(
        soundIds: {'swing': 'sfx/sword.wav'},
        playSound: (path, {double volume = 1.0}) async {
          plays.add(path);
        },
      ).attach(world);
      AnimationShakeSystem(camera).attach(world);
      AnimationParticleSystem().attach(world);

      final player = world.spawn();
      world.storeOf<Position>().set(player, Position(100, 100));
      world.storeOf<PlatformerController>().set(
        player,
        PlatformerController(facingSign: 1),
      );
      world.storeOf<Sprite>().set(player, Sprite('atlas', 'atk_0'));
      world.storeOf<ParticleEmitter>().set(player, ParticleEmitter());
      world.storeOf<Weapon>().set(
        player,
        Weapon(
          kind: WeaponKind.melee,
          meleeHitboxFromAnimation: true,
          meleeRange: 30,
          meleeDurationSeconds: 5,
          cooldownSeconds: 1,
        ),
      );
      world.storeOf<AnimationState>().set(
        player,
        AnimationState(
          AnimationClip(
            'attack',
            ['atk_0', 'atk_1', 'atk_2', 'atk_3'],
            frameDurationSeconds: 0.06,
            loop: false,
            frameEvents: [
              [],
              [const AnimationEvent('sfx', {'id': 'swing'})],
              [
                const AnimationEvent('hitbox_on'),
                const AnimationEvent('shake', {
                  'magnitude': 3,
                  'duration': 0.12,
                  'impulse': true,
                }),
                const AnimationEvent('particle', {'count': 10}),
              ],
              [const AnimationEvent('hitbox_off')],
            ],
          ),
        ),
      );

      world.storeOf<Weapon>().get(player)!.attackRequested = true;
      world.step(0.016);
      expect(world.storeOf<Projectile>().length, 0);

      world.step(0.06); // frame 1 — sfx
      expect(plays, ['sfx/sword.wav']);

      world.step(0.06); // frame 2 — hitbox_on + shake + particle
      expect(world.storeOf<Projectile>().length, 1);
      expect(world.storeOf<ParticleEmitter>().get(player)!.burstCount, 10);
      camera.update(0);
      expect(
        camera.shakeOffset.dx != 0 || camera.shakeOffset.dy != 0,
        isTrue,
      );

      world.step(0.06); // frame 3 — hitbox_off
      expect(world.storeOf<Projectile>().length, 0);
    });
  });

  group('docs/concepts/platformer.md', () {
    test(
      'spawnPlayer attaches health, inventory and a checkpoint; the systems install',
      () {
        final behaviors = BehaviorRegistry();
        final player = spawnPlayer(
          world,
          x: 100,
          y: 100,
          input: InputController().state,
          jumpSpeed: 500,
          maxHealth: 100,
          startingInventory: {'coin': 0},
        );
        installPlatformerSystems(world, player: player, behaviors: behaviors);

        expect(world.storeOf<Health>().get(player)!.max, 100);
        expect(world.storeOf<Inventory>().has(player), isTrue);
        expect(world.storeOf<LastCheckpoint>().has(player), isTrue);
        expect(world.systemOrder, contains('ai'));

        final bar = spawnHealthHudBar(
          world,
          source: player,
          x: 20,
          y: 20,
          width: 200,
          height: 20,
        );
        world.storeOf<Health>().get(player)!.current = 40;
        world.step(1 / 60);
        expect(
          world.storeOf<HudBar>().get(bar)!.value,
          40,
          reason: 'HealthHudSystem keeps the bar in sync',
        );
      },
    );

    test('damageEntity and healEntity change health', () {
      final player = spawnPlayer(
        world,
        x: 0,
        y: 0,
        input: InputController().state,
        maxHealth: 100,
      );
      damageEntity(world, player, 30);
      expect(world.storeOf<Health>().get(player)!.current, 70);
      healEntity(world, player, 10);
      expect(world.storeOf<Health>().get(player)!.current, 80);
    });

    test(
      'respawnOnDeath puts a dead player back at its last checkpoint with full health',
      () {
        final player = spawnPlayer(
          world,
          x: 10,
          y: 20,
          input: InputController().state,
          maxHealth: 100,
        );
        installProjectileDamage(world);
        trackCheckpoints(world, player);
        respawnOnDeath(world, player, fallbackX: 100, fallbackY: 100);

        world.storeOf<Position>().set(player, Position(500, 500));
        damageEntity(world, player, 1000);
        world.events.flush();

        final pos = world.storeOf<Position>().get(player)!;
        expect(
          (pos.x, pos.y),
          (10, 20),
          reason: 'back at the spawn checkpoint',
        );
        expect(world.storeOf<Health>().get(player)!.current, 100);
      },
    );
  });
}

class _Countdown implements Behavior {
  @override
  Action decide(WorldView view, EntityId self) {
    final state = view.component<AIState>(self)!;
    final ticksLeft = (state.memory['ticksLeft'] as int?) ?? 60;
    state.memory['ticksLeft'] = ticksLeft - 1;
    return const NoOpAction();
  }
}
