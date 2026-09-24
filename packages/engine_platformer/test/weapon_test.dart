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

  group('combo chain', () {
    test('defaults to single hit (no combo)', () {
      final weapon = Weapon();
      expect(weapon.comboCount, 1);
      expect(weapon.comboWindowSeconds, 0.5);
      expect(weapon.currentComboStep, 0);
      expect(weapon.comboTimer, 0);
    });

    test('currentDamage returns base damage when no multipliers', () {
      final weapon = Weapon(damage: 10, comboCount: 3);
      expect(weapon.currentDamage, 10);
    });

    test('currentDamage applies per-step multiplier', () {
      final weapon = Weapon(
        damage: 10,
        comboCount: 3,
        comboDamageMultipliers: [1.0, 1.5, 2.0],
      );
      expect(weapon.currentDamage, 10); // step 0
      weapon.currentComboStep = 1;
      expect(weapon.currentDamage, 15); // step 1
      weapon.currentComboStep = 2;
      expect(weapon.currentDamage, 20); // step 2
    });

    test('currentCooldown returns per-step cooldown', () {
      final weapon = Weapon(
        cooldownSeconds: 0.4,
        comboCount: 3,
        comboCooldowns: [0.3, 0.35, 0.5],
      );
      expect(weapon.currentCooldown, 0.3); // step 0
      weapon.currentComboStep = 1;
      expect(weapon.currentCooldown, 0.35); // step 1
      weapon.currentComboStep = 2;
      expect(weapon.currentCooldown, 0.5); // step 2
    });

    test('advanceCombo increments step and resets at end', () {
      final weapon = Weapon(comboCount: 3);
      expect(weapon.currentComboStep, 0);
      weapon.advanceCombo();
      expect(weapon.currentComboStep, 1);
      weapon.advanceCombo();
      expect(weapon.currentComboStep, 2);
      weapon.advanceCombo();
      expect(weapon.currentComboStep, 0); // resets after last step
    });

    test('resetCombo clears step and timer', () {
      final weapon = Weapon(comboCount: 3, comboTimer: 0.3, currentComboStep: 2);
      weapon.resetCombo();
      expect(weapon.currentComboStep, 0);
      expect(weapon.comboTimer, 0);
    });

    test('round-trips combo fields through toJson/fromJson', () {
      final weapon = Weapon(
        comboCount: 3,
        comboWindowSeconds: 0.6,
        comboTimer: 0.2,
        currentComboStep: 1,
        comboDamageMultipliers: [1.0, 1.2, 1.5],
        comboCooldowns: [0.3, 0.4, 0.5],
        comboMeleeRanges: [24.0, 28.0, 32.0],
        comboMeleeRadii: [12.0, 14.0, 16.0],
        comboMeleeDurations: [0.12, 0.15, 0.18],
      );

      final restored = Weapon.fromJson(weapon.toJson());

      expect(restored.comboCount, 3);
      expect(restored.comboWindowSeconds, 0.6);
      expect(restored.comboTimer, 0.2);
      expect(restored.currentComboStep, 1);
      expect(restored.comboDamageMultipliers, [1.0, 1.2, 1.5]);
      expect(restored.comboCooldowns, [0.3, 0.4, 0.5]);
      expect(restored.comboMeleeRanges, [24.0, 28.0, 32.0]);
      expect(restored.comboMeleeRadii, [12.0, 14.0, 16.0]);
      expect(restored.comboMeleeDurations, [0.12, 0.15, 0.18]);
    });

    test('fromJson defaults combo fields correctly', () {
      final restored = Weapon.fromJson({});
      expect(restored.comboCount, 1);
      expect(restored.comboWindowSeconds, 0.5);
      expect(restored.comboTimer, 0);
      expect(restored.currentComboStep, 0);
      expect(restored.comboDamageMultipliers, isNull);
      expect(restored.comboCooldowns, isNull);
      expect(restored.comboMeleeRanges, isNull);
      expect(restored.comboMeleeRadii, isNull);
      expect(restored.comboMeleeDurations, isNull);
    });
  });
}
