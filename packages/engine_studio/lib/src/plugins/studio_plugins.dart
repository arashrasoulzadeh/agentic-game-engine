import 'package:engine_core/engine_core.dart';
import 'package:flutter/widgets.dart';

/// What a field editor is given: which field of which component it edits, its current value, and the
/// function that writes a new value (through the studio's normal, undoable, schema-checked edit path).
class FieldEditorContext {
  const FieldEditorContext({
    required this.component,
    required this.field,
    required this.value,
    required this.set,
  });

  final String component;
  final FieldSchema field;
  final Object? value;

  /// Applies [value] to the field. A value the schema rejects is refused and shown as the field's error.
  final void Function(Object? value) set;
}

/// Builds a custom control for one component field in the inspector (a colour picker for an ARGB int, a
/// curve editor for a list of points, ...).
typedef FieldEditorBuilder =
    Widget Function(BuildContext context, FieldEditorContext editing);

/// An extension of the studio: extra graph node kinds and custom inspector controls, supplied by a game or a
/// package without touching the studio's code.
///
/// Node kinds added here appear in the graph editor's "add node" menu, are checked by the graph validator
/// and get inspector fields from their `paramsSchema`. They are for **editing and validating**: compiling a
/// graph to engine JSON only knows the built-in kinds, so a game that adds a kind also reads that node
/// from the saved graph itself.
class StudioPlugin {
  const StudioPlugin({
    required this.name,
    this.nodeKinds = const {},
    this.fieldEditors = const {},
  });

  final String name;

  /// New node kinds per graph type.
  final Map<GraphType, Map<String, NodeKind>> nodeKinds;

  /// Custom controls keyed by `'<component>.<field>'` (for example `'sprite.tint'`).
  final Map<String, FieldEditorBuilder> fieldEditors;
}

/// The registered [StudioPlugin]s. Register at startup, before the first screen is built; a later plugin
/// wins when two provide the same kind or field.
class StudioPlugins {
  StudioPlugins._();

  static final List<StudioPlugin> _plugins = [];

  /// The registered plugins, oldest first.
  static List<StudioPlugin> get all => List.unmodifiable(_plugins);

  /// Adds [plugin]. Registering a second plugin with the same name replaces the first.
  static void register(StudioPlugin plugin) {
    _plugins.removeWhere((p) => p.name == plugin.name);
    _plugins.add(plugin);
  }

  /// Removes the plugin called [name], if present.
  static void unregister(String name) =>
      _plugins.removeWhere((p) => p.name == name);

  /// Removes every plugin (for tests).
  static void clear() => _plugins.clear();

  /// The node kinds plugins add to graphs of [type].
  static Map<String, NodeKind> nodeKindsFor(GraphType type) => {
    for (final p in _plugins) ...?p.nodeKinds[type],
  };

  /// The custom control for `'<component>.<field>'`, or null for the default one.
  static FieldEditorBuilder? fieldEditorFor(String component, String field) {
    FieldEditorBuilder? found;
    for (final p in _plugins) {
      found = p.fieldEditors['$component.$field'] ?? found;
    }
    return found;
  }
}
