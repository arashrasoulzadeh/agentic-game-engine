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

    test('table cost curves are validated', () {
      List<String> cost(Map<String, dynamic> c) =>
          problems((j) => (j['generators'] as List)[0]['cost'] = c);
      expect(
        cost({
          'type': 'table',
          'prices': ['5', '9'],
        }),
        isEmpty,
      );
      expect(
        cost({'type': 'table', 'prices': []}),
        contains('generators[0].cost.prices must be a non-empty list'),
      );
      expect(
        cost({
          'type': 'table',
          'prices': ['5', 'x'],
        }),
        contains('generators[0].cost.prices[1] is not a number'),
      );
      expect(
        cost({
          'type': 'table',
          'prices': ['5'],
          'tailGrowth': 0.5,
        }),
        contains('generators[0].cost.tailGrowth must be a number >= 1'),
      );
    });

    test(
      'prestige keepGenerators must name generators; event: stats are known',
      () {
        expect(
          problems(
            (j) => j['prestige'] = {
              'currency': 'gems',
              'basedOn': 'coins',
              'divisor': '1',
              'keepGenerators': ['cursor', 'ghost'],
            },
          ),
          ['prestige.keepGenerators[1] "ghost" is not a generator id'],
        );
        expect(
          problems(
            (j) => j['achievements'] = [
              {'id': 'a', 'stat': 'event:dragon', 'atLeast': '1'},
            ],
          ),
          isEmpty,
        );
      },
    );

    test(
      'prestige layers: a prestiges list loads, ids must be unique, resets must be names',
      () {
        final layered = valid()..remove('prestige');
        (layered['resources'] as Map)['stars'] = <String, dynamic>{};
        layered['prestiges'] = [
          {'currency': 'gems', 'basedOn': 'coins', 'divisor': '1e6'},
          {
            'id': 'ascend',
            'currency': 'stars',
            'basedOn': 'gems',
            'divisor': '100',
            'resetsCurrencies': ['gems'],
          },
        ];
        expect(validateIdleDefinition(layered), isEmpty);
        final w = World(width: 4, height: 4);
        registerCoreComponents(w);
        loadIdleDefinition(w, layered);
        expect(w.storeOf<PrestigeRule>().length, 2);
        expect(prestigeRuleOf(w, 'ascend')!.currency, 'stars');
        expect(prestigeRuleOf(w)!.id, 'prestige');

        expect(
          problems(
            (j) => j['prestiges'] = [
              {'currency': 'a', 'basedOn': 'coins', 'divisor': '1'},
              {'currency': 'b', 'basedOn': 'a', 'divisor': '1'},
            ],
          ),
          contains('prestiges[1].id "prestige" is used twice'),
        );
        expect(
          problems(
            (j) => j['prestiges'] = [
              {
                'id': 'x',
                'currency': 'a',
                'basedOn': 'coins',
                'divisor': '1',
                'resetsCurrencies': [3],
              },
            ],
          ),
          contains(
            'prestiges[0].resetsCurrencies must be a list of currency names',
          ),
        );
        expect(
          problems((j) => j['prestiges'] = 'no'),
          contains('prestiges must be a list'),
        );
      },
    );

    test('synergy upgrades need synergyOf naming a generator', () {
      expect(
        problems(
          (j) => (j['upgrades'] as List)[0] = {
            'id': 'syn',
            'target': 'farm',
            'bonusPerOwned': '0.01',
            'synergyOf': 'cursor',
            'cost': {'coins': '1'},
          },
        ),
        isEmpty,
      );
      expect(
        problems(
          (j) => (j['upgrades'] as List)[0] = {
            'id': 'syn',
            'target': 'farm',
            'bonusPerOwned': '0.01',
            'cost': {'coins': '1'},
          },
        ),
        contains('upgrades[0].synergyOf is required when bonusPerOwned is set'),
      );
      expect(
        problems(
          (j) => (j['upgrades'] as List)[0] = {
            'id': 'syn',
            'target': 'farm',
            'bonusPerOwned': '0.01',
            'synergyOf': 'ghost',
            'cost': {'coins': '1'},
          },
        ),
        contains('upgrades[0].synergyOf "ghost" is not a generator id'),
      );
      expect(
        problems(
          (j) => (j['upgrades'] as List)[0] = {
            'id': 'bare',
            'target': 'cursor',
            'cost': {'coins': '1'},
          },
        ),
        contains('upgrades[0] needs multiplier and/or bonusPerOwned'),
      );
    });

    test(
      'a golden block loads, and bad rewards are reported with their path',
      () {
        final j = valid()
          ..['golden'] = {
            'meanInterval': 120,
            'lifetime': 12,
            'rewards': [
              {'kind': 'boost', 'multiplier': '7', 'seconds': 30, 'weight': 2},
              {'kind': 'payout', 'seconds': 600},
            ],
          };
        expect(validateIdleDefinition(j), isEmpty);
        final w = World(width: 4, height: 4);
        registerCoreComponents(w);
        loadIdleDefinition(w, j);
        final g = w.storeOf<GoldenEvents>().denseAt(0);
        expect(
          (g.meanInterval, g.lifetime, g.rewards.length),
          (120.0, 12.0, 2),
        );

        expect(
          problems(
            (j) => j['golden'] = {
              'meanInterval': 0,
              'lifetime': 'x',
              'rewards': [
                {'kind': 'steal', 'seconds': 5},
                {'kind': 'boost', 'seconds': 0},
              ],
            },
          ),
          containsAll([
            'golden.meanInterval must be a number greater than 0',
            'golden.lifetime must be a number greater than 0',
            'golden.rewards[0].kind must be "boost" or "payout"',
            'golden.rewards[1].seconds must be a number greater than 0',
            'golden.rewards[1].multiplier is not a number',
          ]),
        );
        expect(
          problems(
            (j) =>
                j['golden'] = {'meanInterval': 1, 'lifetime': 1, 'rewards': []},
          ),
          contains('golden.rewards must be a non-empty list'),
        );
      },
    );

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
          'generators[0].cost.type "zigzag" is unknown (use geometric, linear or table)',
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
      expect(
        problems((j) => (j['prestige'] as Map)['currency'] = 'mana'),
        contains('prestige.currency "mana" is not a declared resource'),
      );
      expect(
        problems((j) => (j['prestige'] as Map)['basedOn'] = 'mana'),
        contains('prestige.basedOn "mana" is not a declared resource'),
      );
    });

    test('offline, costResource and requires are checked', () {
      expect(
        problems((j) => j['offline'] = 'later'),
        contains('offline must be an object'),
      );
      expect(
        problems((j) => j['offline'] = {'capHours': 0, 'efficiency': 2}),
        allOf(
          contains('offline.capHours must be a number greater than 0'),
          contains('offline.efficiency must be a number between 0 and 1'),
        ),
      );
      expect(
        problems((j) => (j['generators'] as List)[0]['costResource'] = 'mana'),
        contains(
          'generators[0].costResource "mana" is not a declared resource',
        ),
      );
      expect(
        problems((j) => (j['upgrades'] as List)[0]['cost'] = {'mana': '10'}),
        contains('upgrades[0].cost.mana is not a declared resource'),
      );
      expect(
        problems((j) => (j['generators'] as List)[0]['requires'] = [1]),
        contains('generators[0].requires[0] must be a non-empty string'),
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
