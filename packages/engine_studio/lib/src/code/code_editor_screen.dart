import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'dart_highlighter.dart';
import 'project_symbols.dart';

/// A text editor for one project file. Dart files are coloured as they are typed
/// and offer completions from the project's own names (classes, atlas ids, entity
/// names) and the engine's components. The text saved is exactly what was typed;
/// colouring and completion only change what is shown.
///
/// Saving writes through a temporary file and a rename, so a crash mid-save keeps
/// the old file. Saving does not rebuild the game.
class CodeEditorScreen extends StatefulWidget {
  final String filePath;

  /// The project the file belongs to, for discovering its names. Null means no
  /// project-specific completions.
  final String? projectRoot;

  const CodeEditorScreen({super.key, required this.filePath, this.projectRoot});

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  late final TextEditingController _text;
  late final ProjectSymbols _symbols;
  late String _saved;
  String? _error;

  bool get _isDart => widget.filePath.endsWith('.dart');

  @override
  void initState() {
    super.initState();
    _saved = File(widget.filePath).readAsStringSync();
    _text = _isDart
        ? DartHighlightController(text: _saved)
        : TextEditingController(text: _saved);
    _text.addListener(() => setState(() {}));
    final root = widget.projectRoot;
    _symbols = root == null
        ? const ProjectSymbols(
            classes: {},
            atlasIds: {},
            entityNames: {},
            components: {},
          )
        : ProjectSymbols.scan(root);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _dirty => _text.text != _saved;

  /// The identifier being typed right before the cursor, or '' when there is none.
  String get _wordBeforeCursor {
    final cursor = _text.selection.baseOffset;
    if (cursor < 0) return '';
    final before = _text.text.substring(0, cursor);
    final match = RegExp(r'[A-Za-z_]\w*$').firstMatch(before);
    return match?.group(0) ?? '';
  }

  void _complete(String name) {
    final cursor = _text.selection.baseOffset;
    final word = _wordBeforeCursor;
    final start = cursor - word.length;
    final updated = _text.text.replaceRange(start, cursor, name);
    _text.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + name.length),
    );
  }

  void _save() {
    if (!_dirty) {
      return;
    }
    try {
      final target = File(widget.filePath);
      final temp = File('${widget.filePath}.tmp')
        ..writeAsStringSync(_text.text, flush: true);
      temp.renameSync(target.path);
      setState(() {
        _saved = _text.text;
        _error = null;
      });
    } on FileSystemException catch (e) {
      setState(() => _error = 'Could not save: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = p.basename(widget.filePath);
    final suggestions = _symbols.completionsFor(_wordBeforeCursor);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Text(name),
              if (_dirty)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('•', key: Key('code-dirty')),
                ),
            ],
          ),
          actions: [
            IconButton(
              key: const Key('code-save'),
              tooltip: 'Save (Cmd/Ctrl+S)',
              onPressed: _dirty ? _save : null,
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error!,
                  key: const Key('code-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (suggestions.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final (name, kind) in suggestions.take(12))
                      Padding(
                        padding: const EdgeInsets.only(
                          right: 6,
                          top: 4,
                          bottom: 4,
                        ),
                        child: ActionChip(
                          key: Key('suggest-$name'),
                          avatar: Text(
                            kind,
                            style: const TextStyle(fontSize: 10),
                          ),
                          label: Text(name),
                          onPressed: () => _complete(name),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: TextField(
                key: const Key('code-text'),
                controller: _text,
                expands: true,
                maxLines: null,
                minLines: null,
                style: const TextStyle(fontFamily: 'Menlo', fontSize: 13),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
