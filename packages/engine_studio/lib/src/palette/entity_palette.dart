import 'package:engine_schema/engine_schema.dart';
import 'package:flutter/material.dart';

import '../level/level_editor.dart';

/// The palette of components a designer can place. Every entry comes from the
/// engine's schemas, so a new component appears here without any studio change.
///
/// Picking an entry arms the place tool with that component. The next tap places
/// an entity carrying the component's schema template, which is valid by
/// construction, so placing from the palette never adds a validation error.
class EntityPalette extends StatefulWidget {
  final LevelEditor editor;

  /// Called after the palette changes the editor, so the screen can redraw.
  final VoidCallback onChanged;

  const EntityPalette({
    super.key,
    required this.editor,
    required this.onChanged,
  });

  @override
  State<EntityPalette> createState() => _EntityPaletteState();
}

class _EntityPaletteState extends State<EntityPalette> {
  String _filter = '';

  /// Component names the palette offers, sorted and filtered by the search box.
  List<String> get _names {
    final all = allComponentSchemas.keys.toList()..sort();
    if (_filter.isEmpty) return all;
    final query = _filter.toLowerCase();
    return all.where((name) => name.toLowerCase().contains(query)).toList();
  }

  void _pick(String? component) {
    widget.editor
      ..pendingComponent = component
      ..tool = EditorTool.placeEntity;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.editor.pendingComponent;
    return Container(
      width: 200,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              key: const Key('palette-search'),
              decoration: const InputDecoration(
                hintText: 'Find a component',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (text) => setState(() => _filter = text.trim()),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  key: const Key('palette-empty'),
                  dense: true,
                  selected: pending == null,
                  leading: const Icon(Icons.crop_square),
                  title: const Text('Empty entity'),
                  onTap: () => _pick(null),
                ),
                for (final name in _names)
                  ListTile(
                    key: Key('palette-$name'),
                    dense: true,
                    selected: pending == name,
                    leading: const Icon(Icons.extension_outlined),
                    title: Text(name),
                    onTap: () => _pick(name),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
