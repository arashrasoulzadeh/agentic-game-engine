import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('an alias wins; an unaliased id is prettified, never shown raw', () {
    final a = ActionAliases({'action_0': 'Jump'});
    expect(a.labelFor('action_0'), 'Jump');
    expect(a.labelFor('move_left'), 'Move Left');
    expect(a.labelFor('moveRight'), 'Move Right');
    expect(a.labelFor('dash-attack'), 'Dash Attack');
    expect(a.labelFor('jump'), 'Jump');
    expect(a.labelFor('action_1'), 'Action 1');
  });

  test('set replaces, a blank label clears, hasAlias reflects it', () {
    final a = ActionAliases();
    a.set('jump', 'Leap');
    expect(a.hasAlias('jump'), isTrue);
    expect(a.labelFor('jump'), 'Leap');
    a.set('jump', '   ');
    expect(a.hasAlias('jump'), isFalse);
    expect(a.labelFor('jump'), 'Jump');
  });

  test('prettify leaves an id with nothing to prettify alone', () {
    expect(ActionAliases.prettify('_'), '_');
    expect(ActionAliases.prettify(''), '');
  });

  test('JSON round trip', () {
    final back = ActionAliases.fromJson(ActionAliases({'a': 'A!'}).toJson());
    expect(back.labelFor('a'), 'A!');
  });

  test('the constructor copies its input map', () {
    final src = {'a': 'x'};
    final a = ActionAliases(src);
    src['a'] = 'changed';
    expect(a.labelFor('a'), 'x');
  });
}
