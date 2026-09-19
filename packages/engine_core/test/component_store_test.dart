import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('set on an entity that already has the component overwrites in place', () {
    final store = ComponentStore<Position>();
    store.set(1, Position(0, 0));
    store.set(1, Position(5, 5));

    expect(store.get(1)!.x, 5);
    expect(store.length, 1);
  });

  test(
      'removing the only (last) entry does not leave a dangling entityToDense '
      'mapping for a later set() on a recycled id (regression: found via a '
      'spawn/destroy churn benchmark that crashed with a RangeError)',
      tags: ['regression'], () {
    final store = ComponentStore<Position>();
    store.set(1, Position(1, 1));
    store.remove(1); // 1 was the only entry -- idx == lastIdx == 0

    // Simulates EntityManager recycling id 1 for a brand-new entity.
    store.set(1, Position(9, 9));

    expect(store.get(1)!.x, 9);
    expect(store.length, 1);
  });

  test('remove swaps the last dense entry into the removed slot', () {
    final store = ComponentStore<Position>();
    store.set(1, Position(1, 1));
    store.set(2, Position(2, 2));
    store.set(3, Position(3, 3));

    store.remove(1);

    expect(store.has(1), isFalse);
    expect(store.length, 2);
    expect({store.get(2)!.x, store.get(3)!.x}, {2.0, 3.0});
  });
}
