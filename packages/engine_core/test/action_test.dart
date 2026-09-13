import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('NoOpAction.apply is a genuine no-op', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(1, 2));

    const NoOpAction().apply(world);

    expect(world.storeOf<Position>().get(id)!.x, 1);
    expect(world.storeOf<Position>().get(id)!.y, 2);
  });
}
