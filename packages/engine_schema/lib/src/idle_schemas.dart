import 'field_schema.dart';

// Schemas for components registered by engine_idle. Big numbers are written as strings
// ("1.5e300") in JSON, so those fields are `object`/`string` here.

const generatorSchema = ComponentSchema('generator', [
  FieldSchema('id', FieldType.string, required: true),
  FieldSchema('name', FieldType.string, optional: true),
  FieldSchema('nameKey', FieldType.string, optional: true),
  FieldSchema('owned', FieldType.int, min: 0),
  FieldSchema('maxOwned', FieldType.int, min: 1, optional: true),
  FieldSchema('costResource', FieldType.string),
  FieldSchema('cost', FieldType.object, required: true),
  FieldSchema('output', FieldType.object),
  FieldSchema('requires', FieldType.list),
  FieldSchema('milestones', FieldType.list),
]);

const upgradeSchema = ComponentSchema('upgrade', [
  FieldSchema('id', FieldType.string, required: true),
  FieldSchema('name', FieldType.string, optional: true),
  FieldSchema('nameKey', FieldType.string, optional: true),
  FieldSchema('cost', FieldType.object),
  FieldSchema('target', FieldType.string),
  FieldSchema('multiplier', FieldType.string),
  FieldSchema('bonusPerOwned', FieldType.string, optional: true),
  FieldSchema('synergyOf', FieldType.string, optional: true),
  FieldSchema('purchased', FieldType.bool),
  FieldSchema('requires', FieldType.list),
]);

const idleModifiersSchema = ComponentSchema('idleModifiers', [
  FieldSchema('additive', FieldType.object),
  FieldSchema('multiplicative', FieldType.object),
]);

const idleStatsSchema = ComponentSchema('idleStats', [
  FieldSchema('runEarned', FieldType.object),
  FieldSchema('lifetimeEarned', FieldType.object),
  FieldSchema('prestigeCount', FieldType.int, min: 0),
  FieldSchema('taps', FieldType.int, min: 0),
  FieldSchema('secondsPlayed', FieldType.double, min: 0),
  FieldSchema('eventCounts', FieldType.object),
]);

const prestigeRuleSchema = ComponentSchema('prestigeRule', [
  FieldSchema('currency', FieldType.string, required: true),
  FieldSchema('basedOn', FieldType.string, required: true),
  FieldSchema('divisor', FieldType.string),
  FieldSchema('exponent', FieldType.double, min: 0),
  FieldSchema('bonusPerUnit', FieldType.double, min: 0),
  FieldSchema('startingAmounts', FieldType.object),
  FieldSchema('keepUpgrades', FieldType.bool),
  FieldSchema('keepGenerators', FieldType.list),
  FieldSchema('id', FieldType.string),
  FieldSchema('resetsCurrencies', FieldType.list),
]);

const achievementSchema = ComponentSchema('achievement', [
  FieldSchema('id', FieldType.string, required: true),
  FieldSchema('name', FieldType.string, optional: true),
  FieldSchema('nameKey', FieldType.string, optional: true),
  FieldSchema('stat', FieldType.string, required: true),
  FieldSchema('atLeast', FieldType.string, required: true),
  FieldSchema('reward', FieldType.string),
  FieldSchema('unlocked', FieldType.bool),
]);

const researchNodeSchema = ComponentSchema('researchNode', [
  FieldSchema('id', FieldType.string, required: true),
  FieldSchema('name', FieldType.string, optional: true),
  FieldSchema('nameKey', FieldType.string, optional: true),
  FieldSchema('cost', FieldType.object),
  FieldSchema('requires', FieldType.list),
  FieldSchema('unlocks', FieldType.list),
  FieldSchema('purchased', FieldType.bool),
]);

const timeWarpOfferSchema = ComponentSchema('timeWarpOffer', [
  FieldSchema('id', FieldType.string, required: true),
  FieldSchema('name', FieldType.string, optional: true),
  FieldSchema('nameKey', FieldType.string, optional: true),
  FieldSchema('seconds', FieldType.int, min: 1, required: true),
  FieldSchema('cost', FieldType.object),
]);

const boostSchema = ComponentSchema('boost', [
  FieldSchema('id', FieldType.string, required: true),
  FieldSchema('multiplier', FieldType.string, required: true),
  FieldSchema('remaining', FieldType.double, min: 0, required: true),
]);

const goldenEventsSchema = ComponentSchema('goldenEvents', [
  FieldSchema('meanInterval', FieldType.double, min: 1, required: true),
  FieldSchema('lifetime', FieldType.double, min: 0, required: true),
  FieldSchema('rewards', FieldType.list, required: true),
  FieldSchema('countdown', FieldType.double),
  FieldSchema('offered', FieldType.int, min: 0, optional: true),
  FieldSchema('offerRemaining', FieldType.double, min: 0),
]);

const autoBuyerSchema = ComponentSchema('autoBuyer', [
  FieldSchema('enabled', FieldType.bool),
  FieldSchema('intervalSeconds', FieldType.double, min: 0.01),
  FieldSchema('mainResource', FieldType.string),
  FieldSchema('maxPerRun', FieldType.int, min: 1),
  FieldSchema('elapsed', FieldType.double, min: 0),
]);

const challengeSchema = ComponentSchema('challenge', [
  FieldSchema('id', FieldType.string, required: true),
  FieldSchema('name', FieldType.string, optional: true),
  FieldSchema('rules', FieldType.list),
  FieldSchema('goalStat', FieldType.string, required: true),
  FieldSchema('goalAtLeast', FieldType.string, required: true),
  FieldSchema('reward', FieldType.string),
  FieldSchema('active', FieldType.bool),
  FieldSchema('completed', FieldType.bool),
]);
