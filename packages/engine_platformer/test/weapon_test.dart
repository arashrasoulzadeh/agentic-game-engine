import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to a melee weapon that is ready to fire', () {
    final weapon = Weapon();
    expect(weapon.kind, WeaponKind.melee);
    expect(weapon.isReady, isTrue);
  });

  test('isReady is false while cooldownRemaining is above 0', () {
    final weapon = Weapon(cooldownRemaining: 0.2);
    expect(weapon.isReady, isFalse);
  });

  test('round-trips every field through toJson/fromJson', () {
    final weapon = Weapon(
      kind: WeaponKind.ranged,
      damage: 25,
      cooldownSeconds: 0.6,
      cooldownRemaining: 0.1,
      meleeRange: 30,
      meleeRadius: 14,
      meleeDurationSeconds: 0.2,
      projectileSpeed: 500,
      projectileRadius: 6,
      projectileLifetimeSeconds: 4,
      atlasId: 'weapons',
      spriteRegion: 'bullet',
    );

    final restored = Weapon.fromJson(weapon.toJson());

    expect(restored.kind, WeaponKind.ranged);
    expect(restored.damage, 25);
    expect(restored.cooldownSeconds, 0.6);
    expect(restored.cooldownRemaining, 0.1);
    expect(restored.meleeRange, 30);
    expect(restored.meleeRadius, 14);
    expect(restored.meleeDurationSeconds, 0.2);
    expect(restored.projectileSpeed, 500);
    expect(restored.projectileRadius, 6);
    expect(restored.projectileLifetimeSeconds, 4);
    expect(restored.atlasId, 'weapons');
    expect(restored.spriteRegion, 'bullet');
  });

  test('fromJson defaults missing fields to a fresh melee Weapon\'s values', () {
    final restored = Weapon.fromJson({});
    final fresh = Weapon();

    expect(restored.kind, fresh.kind);
    expect(restored.damage, fresh.damage);
    expect(restored.cooldownSeconds, fresh.cooldownSeconds);
    expect(restored.atlasId, isNull);
    expect(restored.spriteRegion, isNull);
  });

  test('an unrecognized kind string falls back to melee rather than throwing', () {
    final restored = Weapon.fromJson({'kind': 'flamethrower'});
    expect(restored.kind, WeaponKind.melee);
  });
}
