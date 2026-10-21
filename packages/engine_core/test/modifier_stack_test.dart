import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

BigNumber n(String s) => BigNumber.parse(s);

void main() {
  test('an empty stack leaves the base alone', () {
    expect(ModifierStack().apply(n('7')), n('7'));
    expect(ModifierStack().totalMultiplier, BigNumber.one);
  });

  test('flat bonuses add to the base, then multipliers multiply the sum', () {
    final s = ModifierStack()
      ..setAdditive('cursor', n('2'))
      ..setAdditive('grandma', n('3'))
      ..setMultiplier('prestige', n('2'))
      ..setMultiplier('boost', n('1.5'));
    expect(
      s.apply(n('5')).approxEquals(n('30')),
      isTrue,
      reason: '(5 + 2 + 3) * 2 * 1.5',
    );
    expect(s.totalMultiplier, n('3'));
  });

  test('the order bonuses were added in never changes the result', () {
    final a = ModifierStack()
      ..setMultiplier('x', n('3'))
      ..setAdditive('y', n('4'))
      ..setMultiplier('z', n('5'));
    final b = ModifierStack()
      ..setMultiplier('z', n('5'))
      ..setAdditive('y', n('4'))
      ..setMultiplier('x', n('3'));
    expect(a.apply(n('10')), b.apply(n('10')));
    expect(a.apply(n('10')).approxEquals(n('210')), isTrue);
  });

  test('setting a source again replaces it; removing takes it away', () {
    final s = ModifierStack()..setMultiplier('boost', n('2'));
    s.setMultiplier('boost', n('10'));
    expect(s.apply(n('1')), n('10'));
    expect(s.remove('boost'), isTrue);
    expect(s.remove('boost'), isFalse);
    expect(s.apply(n('1')), n('1'));
    expect(s.sources, isEmpty);
  });

  test('the breakdown explains the total step by step, in a stable order', () {
    final s = ModifierStack()
      ..setMultiplier('prestige', n('2'))
      ..setAdditive('b_upgrade', n('3'))
      ..setAdditive('a_upgrade', n('1'));
    final steps = s.breakdown(n('4'));
    expect(steps.map((x) => (x.source, x.operation)), [
      ('base', '='),
      ('a_upgrade', '+'),
      ('b_upgrade', '+'),
      ('prestige', '*'),
    ]);
    expect(steps.last.running, s.apply(n('4')));
    expect(steps.last.running.approxEquals(n('16')), isTrue);
  });

  test('works at idle-game scale and survives JSON', () {
    final s = ModifierStack()
      ..setMultiplier('prestige', n('1e40'))
      ..setMultiplier('boost', n('7'))
      ..setAdditive('flat', n('1e3'));
    final back = ModifierStack.fromJson(
      jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
    );
    expect(back.apply(n('1e6')), s.apply(n('1e6')));
    expect(back.sources, s.sources);
    expect(s.apply(n('1e6')).approxEquals(n('7.007e46')), isTrue);
  });
}
