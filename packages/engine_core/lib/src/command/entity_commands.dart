import '../content/level_document.dart';
import 'edit_command.dart';

/// Adds [entity] to the end of the document, or at [index] when given.
class AddEntityCommand implements EditCommand {
  final LevelEntity entity;
  final int? index;

  AddEntityCommand(this.entity, {this.index});

  @override
  String get label =>
      'Add entity${entity.name == null ? '' : ' ${entity.name}'}';

  @override
  void apply(LevelDocument document) {
    final at = index ?? document.entities.length;
    document.entities.insert(at, entity);
  }

  @override
  void revert(LevelDocument document) {
    document.entities.remove(entity);
  }
}

/// Removes [entity] from the document. The position it held is recorded at
/// apply time so [revert] puts it back in the same place.
class RemoveEntityCommand implements EditCommand {
  final LevelEntity entity;
  int? _index;

  RemoveEntityCommand(this.entity);

  @override
  String get label =>
      'Remove entity${entity.name == null ? '' : ' ${entity.name}'}';

  @override
  void apply(LevelDocument document) {
    _index = document.entities.indexOf(entity);
    document.entities.remove(entity);
  }

  @override
  void revert(LevelDocument document) {
    document.entities.insert(_index!, entity);
  }
}

/// Sets one field of one component on [entity], creating the component if it
/// is absent. Revert restores the previous value, or removes the component if
/// this command created it.
class SetComponentFieldCommand implements EditCommand {
  final LevelEntity entity;
  final String component;
  final String field;
  final Object? value;

  bool _componentExisted = false;
  bool _fieldExisted = false;
  Object? _previous;

  SetComponentFieldCommand({
    required this.entity,
    required this.component,
    required this.field,
    required this.value,
  });

  @override
  String get label => 'Set $component.$field';

  @override
  void apply(LevelDocument document) {
    _componentExisted = entity.components.containsKey(component);
    final fields = entity.components.putIfAbsent(component, () => {});
    _fieldExisted = fields.containsKey(field);
    _previous = fields[field];
    fields[field] = value;
  }

  @override
  void revert(LevelDocument document) {
    final fields = entity.components[component]!;
    if (_fieldExisted) {
      fields[field] = _previous;
    } else {
      fields.remove(field);
    }
    if (!_componentExisted) entity.components.remove(component);
  }
}

/// Moves [entity] to ([x], [y]) by setting its `position` component. Revert
/// restores the previous `position` exactly, or removes it if there was none.
class MoveEntityCommand implements EditCommand {
  final LevelEntity entity;
  final double x;
  final double y;

  Map<String, dynamic>? _previous;
  bool _existed = false;

  MoveEntityCommand({required this.entity, required this.x, required this.y});

  @override
  String get label => 'Move ${entity.name ?? 'entity'}';

  @override
  void apply(LevelDocument document) {
    _existed = entity.components.containsKey('position');
    _previous = entity.components['position'];
    entity.components['position'] = {'x': x, 'y': y};
  }

  @override
  void revert(LevelDocument document) {
    if (_existed) {
      entity.components['position'] = _previous!;
    } else {
      entity.components.remove('position');
    }
  }
}
