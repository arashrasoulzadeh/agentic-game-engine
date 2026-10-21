import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

BigNumber n(String s) => BigNumber.parse(s);

void main() {
  test('spend is all-or-nothing and canAfford agrees', () {
    final t = BigTreasury(amounts: {'gold': n('50'), 'gems': n('1e30')});
    expect(t.canAfford({'gold': n('50'), 'gems': n('1e30')}), isTrue);
    expect(t.canAfford({'gold': n('50.001')}), isFalse);
    expect(t.spend({'gold': n('20'), 'gems': n('2e30')}), isFalse);
    expect(
      (t.of('gold'), t.of('gems')),
      (n('50'), n('1e30')),
      reason: 'a failed spend takes nothing',
    );
    expect(t.spend({'gold': n('20'), 'gems': n('4e29')}), isTrue);
    expect(t.of('gold'), n('30'));
    expect(t.of('gems').approxEquals(n('6e29')), isTrue);
    expect(t.of('iron'), BigNumber.zero);
    expect(t.canAfford({}), isTrue);
  });

  test('amounts far past a 64-bit int are held and spent exactly enough', () {
    final t = BigTreasury(amounts: {'coins': n('1e100')});
    t.add('coins', n('1e100'));
    expect(t.of('coins'), n('2e100'));
    expect(t.spend({'coins': n('1.5e100')}), isTrue);
    expect(t.of('coins').approxEquals(n('5e99')), isTrue);
  });

  test('income accrues as rate times time, for any step size', () {
    final fast = BigTreasury(incomePerSecond: {'gold': n('3')});
    for (var i = 0; i < 21600; i++) {
      fast.accrue(1);
    }
    final slow = BigTreasury(incomePerSecond: {'gold': n('3')});
    slow.accrue(21600); // one six-hour step, as offline catch-up does
    expect(slow.of('gold'), n('64800'));
    expect(fast.of('gold').approxEquals(slow.of('gold')), isTrue);
  });

  test('a tiny rate over a huge time is correct (1e-3/s for 1e9 s)', () {
    final t = BigTreasury(incomePerSecond: {'x': n('1e-3')});
    t.accrue(1e9);
    expect(t.of('x').approxEquals(n('1e6')), isTrue);
  });

  test(
    'fractions are kept, not rounded away (no lost income at slow rates)',
    () {
      final t = BigTreasury(incomePerSecond: {'x': n('0.5')});
      for (var i = 0; i < 4; i++) {
        t.accrue(0.5);
      }
      expect(t.of('x').approxEquals(n('1')), isTrue);
      expect(t.of('x').floor(), n('1'));
    },
  );

  test('a zero or negative dt changes nothing', () {
    final t = BigTreasury(incomePerSecond: {'x': n('5')});
    t.accrue(0);
    t.accrue(-3);
    expect(t.of('x'), BigNumber.zero);
  });

  test('JSON round-trips exactly, and survives a real encode/decode', () {
    final t = BigTreasury(
      amounts: {'gold': n('1.2345e250'), 'gems': n('7')},
      incomePerSecond: {'gold': n('9.9e240')},
    );
    final back = BigTreasury.fromJson(
      jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>,
    );
    expect(back.of('gold'), t.of('gold'));
    expect(back.of('gems'), t.of('gems'));
    expect(back.rateOf('gold'), t.rateOf('gold'));
    expect(BigTreasury.fromJson({}).amounts, isEmpty);
  });

  test(
    'it is a registered component, so it saves with the world and survives a snapshot',
    () {
      final w = World(width: 10, height: 10);
      registerCoreComponents(w);
      final e = w.spawn();
      w.storeOf<BigTreasury>().set(
        e,
        BigTreasury(
          amounts: {'gold': n('1e500')},
          incomePerSecond: {'gold': n('1e498')},
        ),
      );
      final snap = WorldSnapshot.capture(w);
      final w2 = World(width: 10, height: 10);
      registerCoreComponents(w2);
      snap.restoreInto(w2);
      expect(w2.storeOf<BigTreasury>().get(e)!.of('gold'), n('1e500'));
    },
  );

  test(
    'the old int Treasury is untouched, so existing saves load as before',
    () {
      final old = Treasury.fromJson({
        'team': 'red',
        'amounts': {'gold': 5},
      });
      expect(old.of('gold'), 5);
    },
  );
}
