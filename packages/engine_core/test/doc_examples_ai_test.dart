// The samples in docs/concepts/ai.md, executed so the guide cannot drift.
import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

/// A behavior that runs a closure, so a test can see when a tree reaches it.
class _Do implements Behavior {
  _Do(this.run, {this.fails = false});
  final void Function() run;
  final bool fails;

  @override
  Action decide(WorldView view, EntityId self) {
    run();
    return fails ? const FailureAction() : const NoOpAction();
  }
}

void main() {
  late World world;
  late EntityId guard;
  late BehaviorRegistry behaviors;
  final log = <String>[];

  setUp(() {
    log.clear();
    world = World(width: 100, height: 100);
    registerCoreComponents(world);
    guard = world.spawn();
    behaviors = BehaviorRegistry()
      ..register('see_player', _Do(() => log.add('see'), fails: true))
      ..register('chase', _Do(() => log.add('chase')))
      ..register('patrol', _Do(() => log.add('patrol')));
  });

  test(
    'a behavior tree from JSON runs each tick: selector tries chase, falls back to patrol',
    () {
      // "If I can see the player, chase; otherwise patrol."
      final tree = {
        'type': 'selector',
        'id': 'root',
        'children': [
          {
            'type': 'sequence',
            'id': 'attack',
            'children': [
              {'type': 'leaf', 'id': 'look', 'behaviorId': 'see_player'},
              {'type': 'leaf', 'id': 'go', 'behaviorId': 'chase'},
            ],
          },
          {'type': 'leaf', 'id': 'walk', 'behaviorId': 'patrol'},
        ],
      };
      world.storeOf<AIState>().set(
        guard,
        AIState('tree', memory: {'_bt_root': tree}),
      );
      world.addSystem(BehaviorTreeSystem(behaviors));

      world.step(1 / 60);
      // see_player reports failure, so the sequence stops before chase.
      expect(log, ['see', 'patrol']);
    },
  );

  test('trees are data: they round-trip through JSON unchanged', () {
    final tree = BTSequence(
      id: 'seq',
      children: [
        BTLeaf(id: 'a', behaviorId: 'patrol'),
        BTTimer(id: 't', duration: 1),
      ],
    );
    // Trees are data: this is exactly what you would load from assets/ai/guard.json.
    expect(BTNode.fromJson(tree.toJson()).toJson(), tree.toJson());
  });

  test(
    'a state machine from JSON: named conditions are bound by the game, and the state persists',
    () {
      final json = {
        'id': 'guard',
        'currentState': 'patrol',
        'states': {
          'patrol': {
            'name': 'patrol',
            'behaviorTree': {'type': 'leaf', 'id': 'p', 'behaviorId': 'patrol'},
            'transitions': {
              'chase': {'toState': 'chase', 'condition': 'player_visible'},
            },
          },
          'chase': {
            'name': 'chase',
            'behaviorTree': {'type': 'leaf', 'id': 'c', 'behaviorId': 'chase'},
            'transitions': {
              'patrol': {'toState': 'patrol', 'condition': 'player_lost'},
            },
          },
        },
      };
      var visible = false;
      final system = StateMachineSystem(
        behaviors,
        conditions: {
          'player_visible': (ctx) => visible,
          'player_lost': (ctx) => !visible,
        },
      );
      world.storeOf<AIState>().set(
        guard,
        AIState('fsm', memory: {'_fsm_root': json}),
      );
      world.addSystem(system);

      world.step(1 / 60);
      expect(log, ['patrol']);

      visible = true;
      world.step(1 / 60);
      world.step(1 / 60);
      // The transition happened once and *stayed*: the second tick is still chasing
      // instead of restarting from "patrol".
      expect(log, ['patrol', 'chase', 'chase']);
      expect(json['currentState'], 'chase');

      visible = false;
      world.step(1 / 60);
      expect(log.last, 'patrol');
    },
  );

  test(
    'an unbound condition name never fires (a typo leaves the machine idle)',
    () {
      final t = FSMTransition.fromJson({
        'toState': 'x',
        'condition': 'no_such',
      });
      expect(t.condition(BTContext(WorldView(world), guard)), isFalse);
      expect(t.toJson(), {'toState': 'x', 'condition': 'no_such'});
    },
  );

  group('steering', () {
    test(
      'seek heads straight at the target at full speed; arrive slows inside the radius',
      () {
        final v = seek(Position(0, 0), Position(30, 40), 100);
        expect((v.x, v.y), (60, 80), reason: 'a 3-4-5 triangle, 100 units/s');
        expect(
          arrive(Position(0, 0), Position(300, 0), 100, 50).x,
          100,
          reason: 'far away: full speed',
        );
        expect(
          arrive(Position(0, 0), Position(25, 0), 100, 50).x,
          50,
          reason: 'half way into the slow radius',
        );
        expect(
          arrive(Position(5, 5), Position(5, 5), 100, 50).x,
          0,
          reason: 'there already',
        );
      },
    );

    test(
      'wander keeps the speed and is reproducible for a seeded generator',
      () {
        List<double> run() {
          final rng = DeterministicRandom(7);
          var v = Velocity(1, 0);
          final out = <double>[];
          for (var i = 0; i < 5; i++) {
            v = wander(v, 0.5, 40, rng);
            out.add(v.x);
            expect(v.x * v.x + v.y * v.y, closeTo(40 * 40, 1e-6));
          }
          return out;
        }

        expect(run(), run());
      },
    );
  });

  test('hearing: a sound in range is remembered; one out of range is not', () {
    world.addSystem(HearingSystem());
    final guardPos = Position(100, 100);
    world.storeOf<Position>().set(guard, guardPos);
    world.storeOf<HearingComponent>().set(guard, HearingComponent(range: 200));
    world.storeOf<AIState>().set(guard, AIState('idle'));

    world.events.emit(
      const SoundEvent(x: 150, y: 100, loudness: 120, tag: 'footstep'),
    );
    world.step(1 / 60);
    final heard =
        world.storeOf<AIState>().get(guard)!.memory['lastHeardSound'] as Map;
    expect(heard['x'], 150);
    expect(heard['tag'], 'footstep');

    world.storeOf<AIState>().get(guard)!.memory.clear();
    world.events.emit(
      const SoundEvent(x: 400, y: 100, loudness: 120),
    ); // 300 away, louder than range or not
    world.step(1 / 60);
    expect(
      world.storeOf<AIState>().get(guard)!.memory.containsKey('lastHeardSound'),
      isFalse,
    );
  });
}
