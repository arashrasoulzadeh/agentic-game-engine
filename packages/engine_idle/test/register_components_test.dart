import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registerIdleComponents can be called on a world with the core components, more than once', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    registerIdleComponents(world);
    registerIdleComponents(world);
    expect(world.toJson(), isNotNull);
  });
}
