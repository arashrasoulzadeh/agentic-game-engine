import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_strategy/engine_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('installStrategySystems registers its systems in this order', () {
    final world = World(width: 320, height: 320);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    installStrategySystems(
      world,
      navigator: GridNavigator(cols: 10, rows: 10, terrainCost: (c, r) => 1),
      cellSize: 32,
    );
    expect(world.systemOrder, [
      'orders',
      'turn',
      'winCondition',
      'gridToWorld',
      'selectionMarkers',
    ]);
  });
}
