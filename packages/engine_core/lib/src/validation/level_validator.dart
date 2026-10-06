import '../content/level_document.dart';
import '../ecs/component_registry.dart';

/// One problem found in a [LevelDocument]: which entity, which component (when
/// the problem is inside one), and a message that names the field. The studio
/// shows [message] verbatim, so it says what is wrong rather than just "invalid".
class LevelIssue {
  final int entityIndex;
  final String? entityName;
  final String? component;
  final String message;

  const LevelIssue({
    required this.entityIndex,
    required this.entityName,
    required this.component,
    required this.message,
  });

  @override
  String toString() {
    final where = entityName ?? 'entities[$entityIndex]';
    final inside = component == null ? '' : '.$component';
    return '$where$inside: $message';
  }
}

/// Checks a [LevelDocument] against the components registered in [components].
///
/// Used by the studio for its live validation panel and by `game_agent studio
/// validate` in CI, so both report the same problems. Checks return every
/// issue, not only the first, so a designer can fix them in one pass.
class LevelValidator {
  final ComponentRegistry components;

  const LevelValidator(this.components);

  /// Every issue in [document], in entity order. Empty when the level is valid.
  List<LevelIssue> validate(LevelDocument document) {
    final issues = <LevelIssue>[];
    for (var i = 0; i < document.entities.length; i++) {
      final entity = document.entities[i];
      for (final entry in entity.components.entries) {
        final name = entry.key;
        final schema = components.schemaFor(name);
        if (schema == null) {
          issues.add(
            LevelIssue(
              entityIndex: i,
              entityName: entity.name,
              component: name,
              message: !components.isRegistered(name)
                  ? 'unknown component "$name"'
                  : 'component "$name" has no schema, so its fields cannot be checked',
            ),
          );
          continue;
        }
        for (final message in schema.validate(entry.value)) {
          issues.add(
            LevelIssue(
              entityIndex: i,
              entityName: entity.name,
              component: name,
              message: message,
            ),
          );
        }
      }
    }
    return issues;
  }
}
