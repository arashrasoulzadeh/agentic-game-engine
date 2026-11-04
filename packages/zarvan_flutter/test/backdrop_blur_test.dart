import 'package:flutter/material.dart' hide Velocity, Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart';

void main() {
  test(
    'BackdropBlur survives a JSON round trip and is a registered component',
    () {
      final world = World(width: 100, height: 100);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      final e = world.spawn();
      world.componentsOf<BackdropBlur>().set(
        e,
        BackdropBlur(sigma: 4, belowZIndex: 140),
      );
      final copy = BackdropBlur.fromJson(
        world.componentsOf<BackdropBlur>().get(e)!.toJson(),
      );
      expect(copy.sigma, 4);
      expect(copy.belowZIndex, 140);
      expect(world.components.isRegistered('backdropBlur'), isTrue);
    },
  );

  for (final sigma in [0.0, 5.0]) {
    testWidgets('EngineView paints with a backdrop blur of sigma $sigma', (
      tester,
    ) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      final e = world.spawn();
      world.componentsOf<BackdropBlur>().set(
        e,
        BackdropBlur(sigma: sigma, belowZIndex: 10),
      );
      final t = world.spawn();
      world.componentsOf<Position>().set(t, Position(50, 50));
      world.componentsOf<Text>().set(t, Text('below', zIndex: 0));
      final u = world.spawn();
      world.componentsOf<Position>().set(u, Position(50, 100));
      world.componentsOf<Text>().set(u, Text('above', zIndex: 20));

      await tester.pumpWidget(
        MaterialApp(
          home: EngineView(
            world: world,
            atlasRegistry: AtlasRegistry(),
            camera: Camera(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      expect(find.byType(EngineView), findsOneWidget);
    });
  }
}
