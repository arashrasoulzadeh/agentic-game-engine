import 'dart:math' as math;

import '../level/wave_plan.dart';
import 'gear.dart';

/// What enemies drop and how good it is. Pass to `WaveCombatConfig.loot`.
class LootTable {
  const LootTable({
    this.normalChance = 0.05,
    this.eliteChance = 0.6,
    this.treasureChance = 1,
    this.bonusByRarity = const {
      GearRarity.common: 0.06,
      GearRarity.rare: 0.12,
      GearRarity.epic: 0.22,
    },
    this.waveGrowth = 0.02,
    this.slots = const [
      LootSlot('weapon', 'attack', ['Sword', 'Spear', 'Axe']),
      LootSlot('armor', 'hp', ['Mail', 'Cuirass', 'Helm']),
      LootSlot('charm', 'armor', ['Amulet', 'Ring', 'Talisman']),
    ],
  });

  /// Drop chance by enemy kind.
  final double normalChance;
  final double eliteChance;
  final double treasureChance;

  /// Base bonus per rarity, before [waveGrowth] per wave reached.
  final Map<GearRarity, double> bonusByRarity;
  final double waveGrowth;
  final List<LootSlot> slots;

  double chanceFor(WaveKind kind) => switch (kind) {
    WaveKind.normal => normalChance,
    WaveKind.elite => eliteChance,
    WaveKind.treasure => treasureChance,
  };

  /// Rolls a drop for killing a [kind] enemy on wave [waveIndex]; null when
  /// nothing drops. Elites and treasure enemies drop better rarities.
  Gear? roll(math.Random random, WaveKind kind, int waveIndex) {
    if (slots.isEmpty || random.nextDouble() >= chanceFor(kind)) return null;
    final rarityRoll = random.nextDouble();
    final rarity = switch (kind) {
      WaveKind.treasure => rarityRoll < 0.5 ? GearRarity.rare : GearRarity.epic,
      WaveKind.elite =>
        rarityRoll < 0.15
            ? GearRarity.epic
            : rarityRoll < 0.6
            ? GearRarity.rare
            : GearRarity.common,
      WaveKind.normal =>
        rarityRoll < 0.05
            ? GearRarity.epic
            : rarityRoll < 0.25
            ? GearRarity.rare
            : GearRarity.common,
    };
    final slot = slots[random.nextInt(slots.length)];
    final base = bonusByRarity[rarity] ?? 0.05;
    return Gear(
      slot: slot.slot,
      name: slot.names[random.nextInt(slot.names.length)],
      stat: slot.stat,
      bonus: base * (1 + waveGrowth * waveIndex),
      rarity: rarity,
    );
  }
}

/// One equipment slot: which stat it raises and what its items are called.
class LootSlot {
  const LootSlot(this.slot, this.stat, this.names);

  final String slot;
  final String stat;
  final List<String> names;
}
