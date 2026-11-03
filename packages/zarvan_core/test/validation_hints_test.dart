import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_schema/zarvan_schema.dart';
import 'package:test/test.dart';

LevelDocument _doc(String component) => LevelDocument.fromJson({
  'entities': [
    {
      'name': 'hero',
      'components': {
        component: {'x': 1.0, 'y': 2.0},
      },
    },
  ],
});

void main() {
  test('a typo\'d component name in a registry validator suggests the fix', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final issues = LevelValidator.forRegistry(
      world.components,
    ).validate(_doc('positon'));
    expect(issues.single.message, contains('did you mean "position"?'));
  });

  test('the schema-map validator (CLI, studio, doctor) suggests it too', () {
    final issues = LevelValidator.forSchemas(
      allComponentSchemas,
    ).validate(_doc('velocty'));
    expect(issues.single.message, contains('did you mean "velocity"?'));
  });

  test('checkComponent (strict load, patches) suggests it too', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final problem = world.components.checkComponent('colider', {'radius': 1});
    expect(problem, contains('did you mean "collider"?'));
    expect(problem, contains('registered:'));
  });

  test('a name nothing like any component gets no suggestion', () {
    final issues = LevelValidator.forSchemas(
      allComponentSchemas,
    ).validate(_doc('warpDrive'));
    expect(issues.single.message, 'unknown component "warpDrive"');
  });

  test('a missing required field in a level says what to add', () {
    final issues = LevelValidator.forSchemas(allComponentSchemas).validate(
      LevelDocument.fromJson({
        'entities': [
          {
            'name': 'hero',
            'components': {
              'position': {'x': 1.0},
            },
          },
        ],
      }),
    );
    expect(issues.single.message, 'y is missing (add "y": 0)');
  });
}
