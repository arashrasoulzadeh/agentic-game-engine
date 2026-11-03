import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

World _world() {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  return w;
}

void main() {
  test('a missing field names the data and the expected fields', () {
    final w = _world();
    final id = w.spawn();
    try {
      w.components.applyToEntity(id, {
        'position': {'x': 1},
      });
      fail('should throw');
    } on ComponentApplyException catch (e) {
      final text = e.toString();
      expect(text, contains('component "position" on entity $id'));
      expect(text, contains('missing or has the wrong type'));
      expect(text, contains('{x: 1}'));
      expect(text, contains('x (double, required)'));
      expect(text, isNot(contains('is not a subtype')));
    }
  });

  test('checkComponent gives the same explanation', () {
    final w = _world();
    final problem = w.components.checkComponent('position', {'x': 'a', 'y': 1});
    expect(problem, contains('{x: a, y: 1}'));
    expect(problem, contains('y (double, required)'));
    expect(w.components.checkComponent('position', {'x': 1, 'y': 2}), isNull);
  });

  test('non-cast failures keep their own message', () {
    final w = _world();
    w.components.register<_Picky>(
      'picky',
      (p) => {},
      (json) => throw FormatException('must be even'),
    );
    expect(
      w.components.checkComponent('picky', <String, dynamic>{}),
      contains('must be even'),
    );
  });
}

class _Picky {}
