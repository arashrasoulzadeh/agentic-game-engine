import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EngineView renders a world containing a TileMap without error',
      (tester) async {
    final world = World(width: 400, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(
          mapEntity,
          TileMap(
            cols: 4,
            rows: 4,
            tileWidth: 20,
            tileHeight: 20,
            tiles: [
              0, 0, 0, 0, //
              0, 1, 2, 0, //
              0, 0, 0, 0, //
              1, 1, 1, 1, //
            ],
            solidTileIds: {1},
            oneWayTileIds: {2},
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: AtlasRegistry(),
        camera: Camera(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });
}
