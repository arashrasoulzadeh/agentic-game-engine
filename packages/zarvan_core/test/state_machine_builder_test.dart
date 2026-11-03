import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

BTContext _ctx() {
  final world = World(width: 10, height: 10);
  return BTContext(WorldView(world), world.spawn());
}

void main() {
  test('builds a machine that starts first and transitions in order', () {
    var seen = false;
    final machine =
        (StateMachineBuilder('guard')
              ..state('patrol')
              ..state('chase')
              ..transition('patrol', 'chase', when: (_) => seen, name: 'sees')
              ..transition('chase', 'patrol', when: (_) => !seen))
            .build();
    expect(machine.currentStateName, 'patrol');
    expect(machine.tryTransition(_ctx()), isFalse);
    seen = true;
    expect(machine.tryTransition(_ctx()), isTrue);
    expect(machine.currentStateName, 'chase');
    expect(
      machine.states['patrol']!.transitions['chase']!.conditionName,
      'sees',
    );
  });

  test('start overrides the first declared state', () {
    final machine =
        (StateMachineBuilder('m')
              ..state('a')
              ..state('b')
              ..start('b'))
            .build();
    expect(machine.currentStateName, 'b');
  });

  test('a state runs its tree', () {
    var ticks = 0;
    final behaviors = BehaviorRegistry()
      ..registerFn('count', (view, self) {
        ticks++;
        return const NoOpAction();
      });
    final machine = (StateMachineBuilder(
      'm',
    )..state('work', tree: BT.leaf('count'))).build();
    machine.tick(_ctx()..set('_bt_registry', behaviors));
    expect(ticks, 1);
  });

  test('wiring mistakes fail at build, naming the known states', () {
    expect(
      () =>
          (StateMachineBuilder('m')
                ..state('a')
                ..transition('a', 'typo', when: (_) => true))
              .build(),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          allOf(contains('typo'), contains('Known: a')),
        ),
      ),
    );
    expect(() => StateMachineBuilder('m').build(), throwsArgumentError);
    expect(
      () =>
          (StateMachineBuilder('m')
                ..state('a')
                ..start('z'))
              .build(),
      throwsArgumentError,
    );
    expect(
      () => StateMachineBuilder('m')
        ..state('a')
        ..state('a'),
      throwsArgumentError,
    );
    expect(
      () => StateMachineBuilder('m').state(
        'a',
        tree: BT.leaf('x'),
        behavior: FunctionBehavior((v, s) => const NoOpAction()),
      ),
      throwsArgumentError,
    );
  });
}
