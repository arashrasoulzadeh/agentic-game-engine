import 'package:test/test.dart';

import 'support.dart';

const skirmish = {
  'entities': [
    {
      'name': 'red',
      'components': {
        'team': {'id': 'red'},
        'gridPosition': {'col': 0, 'row': 0},
        'actionPoints': {'max': 4},
        'unitStats': {'maxHp': 14, 'attack': 5},
      },
    },
    {
      'name': 'blue',
      'components': {
        'team': {'id': 'blue'},
        'gridPosition': {'col': 1, 'row': 0},
        'actionPoints': {'max': 4},
        'unitStats': {'maxHp': 10, 'attack': 3},
      },
    },
  ],
};

void main() {
  test('strategy.rules returns the static catalogue', () async {
    final s = await Scratch.create();
    final r = await s.map('strategy.rules');
    expect(r['genre'], 'turn-based strategy');
    expect((r['orders'] as List), contains('attack'));
    expect((r['ai'] as Map)['aggressive'], isNotEmpty);
  });

  test('simulate_turns runs AI and reports events', () async {
    final s = await Scratch.create();
    final r = await s.map('strategy.simulate_turns', {
      'json': skirmish,
      'turns': 4,
    });
    expect(r['teams'], ['red', 'blue']);
    expect(r['ai'], 'aggressive');
    expect(r['turnsEnded'], greaterThanOrEqualTo(1));
    final events = (r['events'] as List).cast<Map>();
    expect(events.any((e) => e['type'] == 'turnStarted'), isTrue);
    // Adjacent melee units should trade hits within a few turns.
    expect(
      events.any((e) => e['type'] == 'attackResolved' || e['type'] == 'unitDamaged'),
      isTrue,
      reason: '$events',
    );
  });

  test('simulate_turns can finish with a winner', () async {
    final s = await Scratch.create();
    final r = await s.map('strategy.simulate_turns', {
      'json': skirmish,
      'turns': 40,
    });
    expect(r['winner'], isNotNull, reason: '$r');
    expect(
      (r['events'] as List).any((e) => (e as Map)['type'] == 'victory'),
      isTrue,
    );
  });

  test('simulate_turns needs two combat teams', () async {
    final s = await Scratch.create();
    expect(
      await s.failure('strategy.simulate_turns', {
        'json': {
          'entities': [
            {
              'name': 'lone',
              'components': {
                'team': {'id': 'red'},
                'gridPosition': {'col': 0, 'row': 0},
                'actionPoints': {'max': 2},
                'unitStats': {'maxHp': 5, 'attack': 1},
              },
            },
          ],
        },
      }),
      isNotNull,
    );
  });
}
