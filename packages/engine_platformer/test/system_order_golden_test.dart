import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the order installPlatformerSystems registers systems in. Order is
/// load-bearing here (jump must run after tileCollision resolves grounding,
/// movement before collision), so a refactor of how systems are ordered must
/// reproduce this exactly or say why it changed.
List<String> _order({required bool behaviors, required bool animation}) {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  final player = spawnPlayer(
    world,
    x: 0,
    y: 0,
    input: InputController().state,
    jumpSpeed: 400,
    maxHealth: 10,
  );
  installPlatformerSystems(
    world,
    player: player,
    behaviors: behaviors ? BehaviorRegistry() : null,
    includeAnimation: animation,
  );
  return world.systemOrder;
}

void main() {
  const core = [
    'gravity',
    'movement',
    'platformer',
    'tileCollision',
    'waterPhysics',
    'jump',
    'ladder',
    'ledgeGrab',
    'dash',
    'collision',
    'health',
    'hitstun',
    'healthHud',
    'hitFlash',
    'projectile',
    'attack',
  ];
  const animation = [
    'facing',
    'movementAnimation',
    'jumpAnimation',
    'animation',
    'animationTransition',
  ];

  test('with behaviors and animation', () {
    expect(_order(behaviors: true, animation: true), [
      'platformerInput',
      'ai',
      ...core,
      ...animation,
    ]);
  });

  test('without animation', () {
    expect(_order(behaviors: true, animation: false), [
      'platformerInput',
      'ai',
      ...core,
    ]);
  });

  test('without behaviors', () {
    expect(_order(behaviors: false, animation: true), [
      'platformerInput',
      ...core,
      ...animation,
    ]);
  });

  test('jump runs after tile grounding and movement before collision', () {
    final order = _order(behaviors: true, animation: true);
    expect(order.indexOf('jump'), greaterThan(order.indexOf('tileCollision')));
    expect(order.indexOf('movement'), lessThan(order.indexOf('collision')));
  });
}
