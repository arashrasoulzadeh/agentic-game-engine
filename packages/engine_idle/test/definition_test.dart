import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle_logic.dart';
import 'package:flutter_test/flutter_test.dart';

BigNumber n(String s) => BigNumber.parse(s);

Map<String, dynamic> valid() => {
  'resources': {
    'coins': {'start': '10'},
    'gems': {},
  },
  'generators': [
    {
      'id': 'cursor',
      'name': 'Cursor',
      'cost': {'type': 'geometric', 'base': '15', 'growth': 1.15},
      'output': {'coins': '0.1'},
    },
    {
      'id': 'farm',
      'cost': {'type': 'linear', 'base': '100', 'step': '50'},
      'output': {'coins': '8'},
      'maxOwned': 5,
    },
  ],
  'upgrades': [
    {
      'id': 'x2',
      'target': 'cursor',
      'multiplier': '2',
      'cost': {'coins': '100'},
    },
  ],
  'achievements': [
    {
      'id': 'rich',
      'stat': 'lifetime:coins',
      'atLeast': '1000',
      'reward': '1.1',
    },
    {'id': 'cursors', 'stat': 'owned:cursor', 'atLeast': '10'},
  ],
  'prestige': <String, dynamic>{
    'currency': 'gems',
    'basedOn': 'coins',
    'divisor': '1e6',
  },
  'offline': {'capHours': 4, 'efficiency': 0.5},
};

void main() {
  test(
    'a valid definition has no problems and loads into a playable world',
    () {
      expect(validateIdleDefinition(valid()), isEmpty);
      final w = World(width: 10, height: 10);
      registerCoreComponents(w);
      final game = loadIdleDefinition(w, valid());

      expect(game.wallet.of('coins'), n('10'));
      expect(game.wallet.of('gems'), BigNumber.zero);
      expect(game.offline.cap, const Duration(hours: 4));
      expect(game.offline.efficiency, 0.5);
      expect(w.storeOf<Generator>().length, 2);
      expect(w.storeOf<Upgrade>().length, 1);
      expect(w.storeOf<Achievement>().length, 2);
      expect(w.storeOf<PrestigeRule>().length, 1);

      final cursor = w.storeOf<Generator>().entityAt(0);
      game.wallet.add('coins', n('100'));
      expect(buyGenerator(w, game.wallet, cursor).ok, isTrue);
    },
  );

  test(
    'a definition without optional parts still loads (offline defaults apply)',
    () {
      final w = World(width: 10, height: 10);
      registerCoreComponents(w);
      final game = loadIdleDefinition(w, {'generators': []});
      expect(game.offline.cap, const Duration(hours: 8));
      expect(game.offline.efficiency, 1.0);
    },
  );

  group('problems are reported with the path to the field', () {
    List<String> problems(void Function(Map<String, dynamic>) edit) {
      final j = valid();
      edit(j);
      return validateIdleDefinition(j);
    }

    test('bad milestones', () {
      List<String> ms(Object v) =>
          problems((j) => (j['generators'] as List)[0]['milestones'] = v);
      expect(ms('x'), contains('generators[0].milestones must be a list'));
      expect(
        ms([
          {'owned': 0, 'multiplier': '2'},
        ]),
        contains(
          'generators[0].milestones[0].owned must be a whole number >= 1',
        ),
      );
      expect(
        ms([
          {'owned': 5, 'multiplier': 'x'},
        ]),
        contains('generators[0].milestones[0].multiplier is not a number'),
      );
      expect(
        ms([
          {'owned': 5, 'multiplier': '2'},
        ]),
        isEmpty,
      );
    });

    test('missing and duplicate ids', () {
      expect(
        problems((j) => (j['generators'] as List)[0].remove('id')),
        contains('generators[0].id is required'),
      );
      expect(
        problems((j) => (j['generators'] as List)[1]['id'] = 'cursor'),
        contains('generators[1].id "cursor" is used twice'),
      );
      expect(
        problems(
          (j) => (j['upgrades'] as List).add({'id': 'x2', 'multiplier': '2'}),
        ),
        contains('upgrades[1].id "x2" is used twice'),
      );
    });

    test('bad numbers and cost curves', () {
      expect(
        problems(
          (j) => ((j['generators'] as List)[0]['cost'] as Map)['growth'] = 0.9,
        ),
        contains('generators[0].cost.growth must be a number >= 1'),
      );
      expect(
        problems(
          (j) => ((j['generators'] as List)[0]['cost'] as Map)['base'] = 'lots',
        ),
        contains('generators[0].cost.base is not a number'),
      );
      expect(
        problems(
          (j) => ((j['generators'] as List)[0]['cost'] as Map)['base'] = '0',
        ),
        contains('generators[0].cost.base must be greater than 0'),
      );
      expect(
        problems(
          (j) => (j['generators'] as List)[0]['cost'] = {
            'type': 'zigzag',
            'base': '1',
          },
        ),
        contains(
          'generators[0].cost.type "zigzag" is unknown (use geometric or linear)',
        ),
      );
      expect(
        problems((j) => (j['generators'] as List)[1]['maxOwned'] = 0),
        contains('generators[1].maxOwned must be a whole number >= 1'),
      );
    });

    test('references to things that do not exist', () {
      expect(
        problems((j) => (j['upgrades'] as List)[0]['target'] = 'ghost'),
        contains('upgrades[0].target "ghost" is not a generator id'),
      );
      expect(
        problems((j) => (j['generators'] as List)[0]['output'] = {'mana': '1'}),
        contains('generators[0].output.mana is not a declared resource'),
      );
      expect(
        problems((j) => (j['achievements'] as List)[1]['stat'] = 'owned:ghost'),
        contains(
          'achievements[1].stat "owned:ghost" names an unknown generator',
        ),
      );
      expect(
        problems((j) => (j['achievements'] as List)[0]['stat'] = 'wealth'),
        anyElement(contains('achievements[0].stat "wealth" is unknown')),
      );
    });

    test('prestige needs a currency, a resource and a positive divisor', () {
      expect(
        problems((j) => (j['prestige'] as Map).remove('currency')),
        contains('prestige.currency is required'),
      );
      expect(
        problems((j) => (j['prestige'] as Map)['divisor'] = '0'),
        contains('prestige.divisor must be greater than 0'),
      );
      expect(
        problems((j) => (j['prestige'] as Map)['exponent'] = -1),
        contains('prestige.exponent must be greater than 0'),
      );
    });

    test('wrong shapes are reported, not thrown', () {
      expect(
        validateIdleDefinition({'generators': 'x'}),
        contains('generators must be a list'),
      );
      expect(
        validateIdleDefinition({
          'generators': [1],
        }),
        contains('generators[0] must be an object'),
      );
      expect(
        validateIdleDefinition({'resources': 3}),
        contains('resources must be an object'),
      );
    });

    test('every problem is listed at once', () {
      final j = valid();
      (j['generators'] as List)[0].remove('id');
      (j['upgrades'] as List)[0]['target'] = 'ghost';
      (j['prestige'] as Map).remove('basedOn');
      expect(validateIdleDefinition(j).length, greaterThanOrEqualTo(3));
    });
  });

  test(
    'loading an invalid definition throws with all problems and creates nothing',
    () {
      final w = World(width: 10, height: 10);
      registerCoreComponents(w);
      final j = valid();
      (j['generators'] as List)[0].remove('id');
      expect(
        () => loadIdleDefinition(w, j),
        throwsA(
          isA<IdleDefinitionException>().having(
            (e) => e.problems,
            'problems',
            isNotEmpty,
          ),
        ),
      );
      expect(w.entities.count, 0);
    },
  );
}
