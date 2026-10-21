import 'field_schema.dart';

// Schemas for components registered by engine_idle. Big numbers are written as strings
// ("1.5e300") in JSON, so those fields are `object`/`string` here.

const generatorSchema = ComponentSchema('generator', [
  FieldSchema('id', FieldType.string, required: true),
  FieldSchema('name', FieldType.string, optional: true),
  FieldSchema('owned', FieldType.int, min: 0),
  FieldSchema('maxOwned', FieldType.int, min: 1, optional: true),
  FieldSchema('costResource', FieldType.string),
  FieldSchema('cost', FieldType.object, required: true),
  FieldSchema('output', FieldType.object),
  FieldSchema('requires', FieldType.list),
]);

const upgradeSchema = ComponentSchema('upgrade', [
  FieldSchema('id', FieldType.string, required: true),
  FieldSchema('name', FieldType.string, optional: true),
  FieldSchema('cost', FieldType.object),
  FieldSchema('target', FieldType.string),
  FieldSchema('multiplier', FieldType.string),
  FieldSchema('purchased', FieldType.bool),
  FieldSchema('requires', FieldType.list),
]);

const idleModifiersSchema = ComponentSchema('idleModifiers', [
  FieldSchema('additive', FieldType.object),
  FieldSchema('multiplicative', FieldType.object),
]);
