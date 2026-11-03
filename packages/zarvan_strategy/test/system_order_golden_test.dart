import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart';
import 'package:zarvan_strategy/zarvan_strategy.dart';
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
