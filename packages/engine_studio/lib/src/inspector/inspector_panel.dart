import 'dart:convert';

import 'package:engine_schema/engine_schema.dart';
import 'package:flutter/material.dart';

import '../level/level_editor.dart';
import 'entity_inspector.dart';

/// The property panel for the selected entity. One control per schema field,
/// chosen by the field's type. A value the schema rejects is shown under its
/// field and changes nothing. Components the engine has no schema for are shown
/// as read-only JSON.
class InspectorPanel extends StatefulWidget {
  final LevelEditor editor;

  /// Called after an edit lands, so the level view can redraw.
  final VoidCallback onChanged;

  const InspectorPanel({
    super.key,
    required this.editor,
    required this.onChanged,
  });

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  /// Rejection messages by "component.field", cleared when that field next succeeds.
  final Map<String, String> _errors = {};

  void _set(String component, String field, Object? value) {
    final error = EntityInspector(
      widget.editor,
    ).setField(component: component, field: field, value: value);
    setState(() {
      final key = '$component.$field';
      if (error == null) {
        _errors.remove(key);
      } else {
        _errors[key] = error;
      }
    });
    if (error == null) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final components = EntityInspector(widget.editor).components();
    final selected = widget.editor.selected;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: selected == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Select an entity to edit its properties.'),
              ),
            )
          : ListView(
              key: const Key('inspector'),
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  selected.name ?? 'Unnamed entity',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final component in components)
                  _componentSection(component),
              ],
            ),
    );
  }

  Widget _componentSection(InspectedComponent component) {
    final schema = component.schema;
    return ExpansionTile(
      key: Key('component-${component.name}'),
      initiallyExpanded: true,
      title: Text(component.name),
      childrenPadding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      children: schema == null
          ? [
              Text(
                'No schema for this component, so it is shown read-only.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SelectableText(jsonEncode(component.json)),
            ]
          : [for (final field in schema.fields) _fieldRow(component, field)],
    );
  }

  Widget _fieldRow(InspectedComponent component, FieldSchema field) {
    final key = '${component.name}.${field.name}';
    final current = component.json[field.name] ?? field.defaultValue;
    final error = _errors[key];
    final Widget control = switch (field.type) {
      FieldType.bool => Switch(
        key: Key('field-$key'),
        value: current == true,
        onChanged: (v) => _set(component.name, field.name, v),
      ),
      FieldType.enumeration => DropdownButton<String>(
        key: Key('field-$key'),
        isExpanded: true,
        value: field.options.contains(current) ? current as String : null,
        items: [
          for (final option in field.options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: (v) {
          if (v != null) _set(component.name, field.name, v);
        },
      ),
      FieldType.list || FieldType.object => SelectableText(
        '${field.name}: ${jsonEncode(current)}',
        key: Key('field-$key'),
      ),
      _ => _TextFieldRow(
        fieldKey: Key('field-$key'),
        field: field,
        initialText: _asText(current, field.type),
        onSubmit: (text) {
          final parsed = parseFieldText(field, text);
          if (parsed.error != null) {
            setState(() => _errors[key] = parsed.error!);
            return;
          }
          _set(component.name, field.name, parsed.value);
        },
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(field.name)),
              Flexible(child: control),
            ],
          ),
          if (error != null)
            Text(
              error,
              key: Key('error-$key'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  /// The text a text field starts with: vectors as "x, y", everything else as
  /// its plain value.
  String _asText(Object? value, FieldType type) {
    if (value == null) return '';
    if (type == FieldType.vector2 && value is List) return value.join(', ');
    return value.toString();
  }
}

/// A text field that applies its value when submitted, not on every keystroke, so
/// a half-typed number is never sent to the schema check.
class _TextFieldRow extends StatefulWidget {
  final Key fieldKey;
  final FieldSchema field;
  final String initialText;
  final ValueChanged<String> onSubmit;

  const _TextFieldRow({
    required this.fieldKey,
    required this.field,
    required this.initialText,
    required this.onSubmit,
  });

  @override
  State<_TextFieldRow> createState() => _TextFieldRowState();
}

class _TextFieldRowState extends State<_TextFieldRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: TextField(
        key: widget.fieldKey,
        controller: _controller,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onSubmitted: widget.onSubmit,
      ),
    );
  }
}
