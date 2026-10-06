import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// A plain-text editor for one project file: its Dart source or its JSON. It keeps
/// the text as the designer typed it and saves it atomically, so a crash mid-save
/// leaves the old file intact.
///
/// Saving a Dart file does not rebuild the game; the preview runs level data, and
/// the game is rebuilt by its own `flutter run`.
class CodeEditorScreen extends StatefulWidget {
  final String filePath;

  const CodeEditorScreen({super.key, required this.filePath});

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  late final TextEditingController _text;
  late String _saved;
  String? _error;

  @override
  void initState() {
    super.initState();
    _saved = File(widget.filePath).readAsStringSync();
    _text = TextEditingController(text: _saved)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _dirty => _text.text != _saved;

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
