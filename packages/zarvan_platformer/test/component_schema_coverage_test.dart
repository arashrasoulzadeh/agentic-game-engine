import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart';
import 'package:zarvan_platformer/zarvan_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The umbrella check for docs/studio/design.md phase 0.3: every component the three
/// engine packages register must declare a schema. Adding a component without
/// one fails here, so the studio's inspector never silently lacks a field list.
void main() {
  test(
    'every component registered by zarvan_core, zarvan_flutter, and zarvan_platformer has a schema',
    () {
      final world = World(width: 800, height: 480);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      registerPlatformerComponents(world);

      expect(world.components.registeredNames, isNotEmpty);
      for (final name in world.components.registeredNames) {
        expect(
          world.components.schemaFor(name),
          isNotNull,
          reason: '$name has no schema',
        );
      }
    },
  );

  test(
    'every field default in every registered schema is valid for its own field',
    () {
      final world = World(width: 800, height: 480);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      registerPlatformerComponents(world);

      for (final schema in world.components.schemas) {
        for (final field in schema.fields) {
          if (field.defaultValue == null) continue;
          expect(
            field.validate(field.defaultValue),
            isNull,
            reason: '${schema.name}.${field.name} default is invalid',
          );
        }
      }
    },
  );
}
