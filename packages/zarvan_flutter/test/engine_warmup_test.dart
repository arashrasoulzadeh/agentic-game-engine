import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;
import 'package:flutter_test/flutter_test.dart';

World _world() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  return world;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('neededShaders', () {
    test('a world with no lights or normal maps needs nothing', () {
      final world = _world();
      final e = world.spawn();
      world.componentsOf<Position>().set(e, Position(0, 0));
      world.componentsOf<Sprite>().set(e, Sprite('a', 'r'));
      expect(EngineWarmup.neededShaders(world), isEmpty);
    });

    test('a CPU light needs only the ambient lighting shader', () {
      final world = _world();
      world.componentsOf<Light2D>().set(world.spawn(), Light2D());
      expect(EngineWarmup.neededShaders(world), {'ambient'});
    });

    test('a shadow-casting GPU light adds the shadow shader', () {
      final world = _world();
      world.componentsOf<Light2D>().set(
        world.spawn(),
        Light2D(useGpuShadows: true, castsShadows: true),
      );
      expect(EngineWarmup.neededShaders(world), {'ambient', 'gpuShadow'});
    });

    test('a normal-mapped sprite needs the normal map shaders', () {
      final world = _world();
      world.componentsOf<Sprite>().set(
        world.spawn(),
        Sprite('a', 'r')..normalAtlasId = 'n',
      );
      expect(EngineWarmup.neededShaders(world), {'normalMap'});
    });
  });

  testWidgets('run reports only for needed shaders and never throws', (
    tester,
  ) async {
    final empty = _world();
    final seen = <String>[];
    await tester.runAsync(
      () => EngineWarmup.run(empty, report: (f, l) => seen.add(l)),
    );
    expect(seen, ['Warming up']); // nothing to warm: just the final report

    final lit = _world();
    lit.componentsOf<Light2D>().set(lit.spawn(), Light2D());
    final litSeen = <String>[];
    await tester.runAsync(
      () => EngineWarmup.run(lit, report: (f, l) => litSeen.add(l)),
    );
    expect(litSeen.first, 'Warming up lighting');
    expect(litSeen.last, 'Warming up');
  });
}
