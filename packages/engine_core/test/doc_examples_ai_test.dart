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

  test('a behavior tree from JSON runs each tick: selector tries chase, falls back to patrol', () {
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
    world.storeOf<AIState>().set(guard, AIState('tree', memory: {'_bt_root': tree}));
    world.addSystem(BehaviorTreeSystem(behaviors));

    world.step(1 / 60);
    // see_player reports failure, so the sequence stops before chase.
    expect(log, ['see', 'patrol']);
  });

  test('trees are data: they round-trip through JSON unchanged', () {
    final tree = BTSequence(id: 'seq', children: [
      BTLeaf(id: 'a', behaviorId: 'patrol'),
      BTTimer(id: 't', duration: 1),
    ]);
    // Trees are data: this is exactly what you would load from assets/ai/guard.json.
    expect(BTNode.fromJson(tree.toJson()).toJson(), tree.toJson());
  });

  test('a state machine from JSON: named conditions are bound by the game, and the state persists', () {
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
    final system = StateMachineSystem(behaviors, conditions: {
      'player_visible': (ctx) => visible,
      'player_lost': (ctx) => !visible,
    });
    world.storeOf<AIState>().set(guard, AIState('fsm', memory: {'_fsm_root': json}));
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
  });

  test('an unbound condition name never fires (a typo leaves the machine idle)', () {
    final t = FSMTransition.fromJson({'toState': 'x', 'condition': 'no_such'});
    expect(t.condition(BTContext(WorldView(world), guard)), isFalse);
    expect(t.toJson(), {'toState': 'x', 'condition': 'no_such'});
  });
}
