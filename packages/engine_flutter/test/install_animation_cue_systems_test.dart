import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('installAnimationCueSystems attaches particle and optional bridges', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    final camera = Camera();
    installAnimationCueSystems(
      world,
      camera: camera,
      includeDialogueSfx: false,
    );
    expect(world.systemOrder, contains('animationParticle'));
    expect(world.systemOrder, contains('animationShake'));
    expect(world.systemOrder, isNot(contains('animationSfx')));
  });
}
