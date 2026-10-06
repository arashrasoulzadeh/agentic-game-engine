import 'package:engine_core/engine_core.dart';
import 'package:engine_schema/engine_schema.dart';
import 'package:test/test.dart';

ComponentRegistry _registry() {
  final world = World(width: 800, height: 480);
  registerCoreComponents(world);
  return world.components;
}

void main() {
  _schemaMapTests();
  _legendTests();
  final validator = LevelValidator.forRegistry(_registry());

  test('a valid level has no issues', () {
    final doc = LevelDocument.fromJson({
      'entities': [
        {
          'name': 'player',
          'components': {
            'position': {'x': 1.0, 'y': 2.0},
            'pushable': {'pushSpeed': 2.5},
          },
        },
      ],
    });
    expect(validator.validate(doc), isEmpty);
  });

  test('reports an unknown component name, naming the entity', () {
    final doc = LevelDocument.fromJson({
      'entities': [
        {
          'name': 'player',
          'components': {
            'warpDrive': {'speed': 9},
          },
        },
      ],
    });
    final issues = validator.validate(doc);
    expect(issues, hasLength(1));
    expect(issues.single.message, 'unknown component "warpDrive"');
    expect(issues.single.entityName, 'player');
    expect(issues.single.component, 'warpDrive');
  });

  test('reports a field out of range, naming the field', () {
    final doc = LevelDocument.fromJson({
      'entities': [
        {
          'components': {
            'pushable': {'pushSpeed': -1.0},
          },
        },
      ],
    });
    final issues = validator.validate(doc);
    expect(issues.single.message, 'pushSpeed must be at least 0');
    expect(issues.single.entityIndex, 0);
    expect(issues.single.entityName, isNull);
  });

  test('reports every problem in one pass, not just the first', () {
    final doc = LevelDocument.fromJson({
      'entities': [
        {
          'components': {
            'position': {'x': 'left', 'y': 0.0},
            'pushable': {'pushSpeed': -1.0},
          },
        },
        {
          'components': {'warpDrive': {}},
        },
      ],
    });
    final messages = validator.validate(doc).map((i) => i.message).toList();
    expect(
      messages,
      containsAll([
        'x must be a number',
        'pushSpeed must be at least 0',
        'unknown component "warpDrive"',
      ]),
    );
    expect(messages, hasLength(3));
  });

  test(
    'a registered component without a schema is flagged as unchecked, not unknown',
    () {
      final registry = _registry();
      registry.register<int>(
        'unschematized',
        (v) => {'v': v},
        (j) => j['v'] as int,
      );
      final doc = LevelDocument.fromJson({
        'entities': [
          {
            'components': {
              'unschematized': {'v': 1},
            },
          },
        ],
      });
      final issues = LevelValidator.forRegistry(registry).validate(doc);
      expect(issues.single.message, contains('has no schema'));
      expect(issues.single.message, isNot(contains('unknown component')));
    },
  );

  test('LevelIssue.toString names the entity and component', () {
    const issue = LevelIssue(
      entityIndex: 2,
      entityName: 'door',
      component: 'pushable',
      message: 'pushSpeed must be at least 0',
    );
    expect(issue.toString(), 'door.pushable: pushSpeed must be at least 0');
  });
}

void _schemaMapTests() {
  group('LevelValidator.forSchemas', () {
    test('validates against a plain schema map, with no registry', () {
      final validator = LevelValidator.forSchemas(allComponentSchemas);
      final doc = LevelDocument.fromJson({
        'entities': [
          {
            'components': {
              'pushable': {'pushSpeed': -1.0},
              'warpDrive': {},
            },
          },
        ],
      });
      final messages = validator.validate(doc).map((i) => i.message).toList();
      expect(
        messages,
        containsAll([
          'pushSpeed must be at least 0',
          'unknown component "warpDrive"',
        ]),
      );
    });
  });
}

void _legendTests() {
  group('LevelValidator legend tileMap', () {
    LevelDocument withLegend(Map<String, dynamic> map) =>
        LevelDocument.fromJson({
          'entities': [
            {
              'components': {'tileMap': map},
            },
          ],
        });

    test(
      'a legend-authored map with every character in the legend is valid',
      () {
        final validator = LevelValidator.forSchemas(allComponentSchemas);
        final doc = withLegend({
          'tileWidth': 16.0,
          'tileHeight': 16.0,
          'legend': {'.': 0, '#': 1},
          'rows': ['..#', '###'],
        });
        expect(validator.validate(doc), isEmpty);
      },
    );

    test('reports a character the legend does not define, with its row', () {
      final validator = LevelValidator.forSchemas(allComponentSchemas);
      final doc = withLegend({
        'tileWidth': 16.0,
        'tileHeight': 16.0,
        'legend': {'.': 0, '#': 1},
        'rows': ['..#', '..x'],
      });
      final messages = validator.validate(doc).map((i) => i.message).toList();
      expect(messages, ['row 1 uses "x", which is not in the legend']);
    });

    test('reports rows that are not a list of strings', () {
      final validator = LevelValidator.forSchemas(allComponentSchemas);
      final doc = withLegend({
        'tileWidth': 16.0,
        'tileHeight': 16.0,
        'legend': {'.': 0},
        'rows': ['..', 3],
      });
      expect(
        validator.validate(doc).single.message,
        'rows must be a list of strings, one per map row',
      );
    });
  });
}
