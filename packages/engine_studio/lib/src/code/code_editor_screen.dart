import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'dart:async';

import '../lsp/dart_session.dart';
import 'analysis.dart';
import 'completion.dart';
import 'dart_highlighter.dart';
import 'marks.dart';
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

  /// Runs the analyzer. Tests pass a fake; the app uses the default.
  final ProjectAnalyzer? analyzer;

  /// Whether to start the Dart language server for completions. Tests turn it off.
  final bool useLanguageServer;

  const CodeEditorScreen({
    super.key,
    required this.filePath,
    this.projectRoot,
    this.analyzer,
    this.useLanguageServer = true,
  });

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  late final TextEditingController _text;
  late final ProjectSymbols _symbols;
  late String _saved;
  String? _error;
  List<AnalysisIssue>? _issues;
  final FocusNode _editorFocus = FocusNode();
  int _completionIndex = 0;
  bool _completionDismissed = false;
  DartSession? _session;
  StreamSubscription<List<LiveDiagnostic>>? _liveSub;
  List<LiveDiagnostic>? _live;
  String? _hover;
  List<CompletionItem>? _serverItems;
  int _serverRequest = 0;
  bool _analyzing = false;

  bool get _isDart => widget.filePath.endsWith('.dart');

  @override
  void initState() {
    super.initState();
    _saved = File(widget.filePath).readAsStringSync();
    _text = _isDart
        ? DartHighlightController(text: _saved)
        : TextEditingController(text: _saved);
    _text.addListener(_onTextChanged);
    final root = widget.projectRoot;
    if (_isDart && root != null && widget.useLanguageServer) {
      _startServer(root);
    }
    _symbols = root == null
        ? const ProjectSymbols(
            classes: {},
            atlasIds: {},
            entityNames: {},
            components: {},
          )
        : ProjectSymbols.scan(root);
  }

  /// Starts the language server for the project and opens this file in it. If the
  /// server cannot start, completion falls back to the local list.
  Future<void> _startServer(String root) async {
    try {
      final session = await DartSession.open(root);
      if (!mounted) {
        await session.close();
        return;
      }
      session.openFile(widget.filePath, _text.text);
      _liveSub = session.diagnosticsFor(widget.filePath).listen((list) {
        if (!mounted) return;
        setState(() => _live = list);
        _underline(list);
      });
      setState(() => _session = session);
    } on Object {
      // Fall back to the local list; the editor works without the server.
    }
  }

  void _onTextChanged() {
    _session?.change(widget.filePath, _text.text);
    setState(() {
      _completionIndex = 0;
      _completionDismissed = false;
      _serverItems = null;
    });
    _requestServerCompletions();
  }

  /// Asks the server for completions at the cursor. A reply that arrives after the
  /// text has moved on is ignored, so an old list never replaces a newer one.
  Future<void> _requestServerCompletions() async {
    final session = _session;
    if (session == null || !_isDart) {
      return;
    }
    final request = ++_serverRequest;
    final offset = _text.selection.baseOffset;
    if (offset < 0) {
      return;
    }
    final before = _text.text.substring(0, offset);
    final line = '\n'.allMatches(before).length;
    final character = offset - (before.lastIndexOf('\n') + 1);
    try {
      final items = await session.completionsAt(
        widget.filePath,
        line,
        character,
      );
      if (!mounted || request != _serverRequest) {
        return;
      }
      setState(() {
        _serverItems = [
          for (final item in items) CompletionItem(item.insertText, item.kind),
        ];
      });
    } on Object {
      // A failed request leaves the local list in place.
    }
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _session?.close();
    _text.removeListener(_onTextChanged);
    _text.dispose();
    _editorFocus.dispose();
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

  /// Handles keys while the completion list is open: arrows move the selection, Enter
  /// or Tab accepts it, and Escape closes the list. Other keys type as usual.
  KeyEventResult _onEditorKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final keyboard = HardwareKeyboard.instance;
      if (event.logicalKey == LogicalKeyboardKey.f12) {
        _goToDefinition();
        return KeyEventResult.handled;
      }
      final command = keyboard.isControlPressed || keyboard.isMetaPressed;
      if (command && event.logicalKey == LogicalKeyboardKey.keyK) {
        _showHover();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyF &&
          keyboard.isAltPressed &&
          keyboard.isShiftPressed) {
        _format();
        return KeyEventResult.handled;
      }
    }
    final items = _completionItems();
    if (items.isEmpty || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _completionIndex = (_completionIndex + 1) % items.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _completionIndex =
            (_completionIndex - 1 + items.length) % items.length,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) {
      _complete(items[_completionIndex.clamp(0, items.length - 1)].name);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _completionDismissed = true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The suggestions for the word at the cursor, or none in a non-Dart file or
  /// after Escape closed the list.
  List<CompletionItem> _completionItems() {
    if (!_isDart || _completionDismissed) {
      return const [];
    }
    final word = _wordBeforeCursor;
    final server = _serverItems;
    if (server != null && word.isNotEmpty) {
      return [
        for (final item in server)
          if (item.name.startsWith(word)) item,
      ];
    }
    return completionsFor(word, _symbols);
  }

  /// Jumps to where the symbol under the cursor is declared. A declaration in this
  /// file moves the cursor; one in another file opens that file.
  Future<void> _goToDefinition() async {
    final session = _session;
    if (session == null) return;
    final offset = _text.selection.baseOffset;
    if (offset < 0) return;
    final before = _text.text.substring(0, offset);
    final line = '\n'.allMatches(before).length;
    final character = offset - (before.lastIndexOf('\n') + 1);
    final target = await session.definitionAt(widget.filePath, line, character);
    if (target == null || !mounted) return;
    if (p.equals(target.path, widget.filePath)) {
      _jumpToPosition(target.line, target.character);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CodeEditorScreen(
            filePath: target.path,
            projectRoot: widget.projectRoot,
            analyzer: widget.analyzer,
            useLanguageServer: widget.useLanguageServer,
          ),
        ),
      );
    }
  }

  /// Shows what the server knows about the symbol at the cursor: its type and its
  /// documentation. Nothing is shown when the server has nothing for that spot.
  Future<void> _showHover() async {
    final session = _session;
    if (session == null) return;
    final (line, character) = _cursorPosition();
    final text = await session.hoverAt(widget.filePath, line, character);
    if (!mounted) return;
    setState(() => _hover = text ?? 'Nothing to show here.');
  }

  /// The cursor as a 0-based line and character, the way the server counts.
  (int, int) _cursorPosition() {
    final offset = _text.selection.baseOffset.clamp(0, _text.text.length);
    final before = _text.text.substring(0, offset);
    final line = '\n'.allMatches(before).length;
    final character = offset - (before.lastIndexOf('\n') + 1);
    return (line, character);
  }

  /// Formats the file with the language server, as one undoable edit: the whole
  /// formatted text replaces the old one, and the file is marked changed until saved.
  Future<void> _format() async {
    final session = _session;
    if (session == null) return;
    final formatted = await session.formatted(widget.filePath, _text.text);
    if (formatted == null || !mounted || formatted == _text.text) return;
    _text.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: _text.selection.baseOffset.clamp(0, formatted.length),
      ),
    );
  }

  void _jumpToPosition(int line, int character) {
    var offset = 0;
    var current = 0;
    final text = _text.text;
    while (current < line && offset < text.length) {
      if (text.codeUnitAt(offset) == 10) current++;
      offset++;
    }
    final target = (offset + character).clamp(0, text.length);
    _text.selection = TextSelection.collapsed(offset: target);
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
    // The text listener reopens the list on any text change, so this runs after it.
    setState(() => _completionDismissed = true);
  }

  /// Runs the Dart analyzer on the project and keeps the findings for this file. The
  /// analyzer reads the saved files, so unsaved edits are saved first.
  Future<void> _analyze() async {
    final root = widget.projectRoot;
    if (root == null || _analyzing) {
      return;
    }
    if (_dirty) {
      _save();
    }
    setState(() => _analyzing = true);
    final all = await (widget.analyzer ?? ProjectAnalyzer()).analyze(root);
    if (!mounted) {
      return;
    }
    setState(() {
      _analyzing = false;
      _issues = [
        for (final issue in all)
          if (p.equals(issue.file, widget.filePath)) issue,
      ];
    });
  }

  /// Underlines each live problem in the text, from where it starts to where it ends.
  void _underline(List<LiveDiagnostic> diagnostics) {
    final highlighter = _text;
    if (highlighter is! DartHighlightController) return;
    final lineStarts = <int>[0];
    for (var i = 0; i < _text.text.length; i++) {
      if (_text.text.codeUnitAt(i) == 10) lineStarts.add(i + 1);
    }
    int offsetOf(int line, int character) {
      if (line >= lineStarts.length) return _text.text.length;
      return (lineStarts[line] + character).clamp(0, _text.text.length);
    }

    highlighter.marks = [
      for (final d in diagnostics)
        TextMark(
          offsetOf(d.line, d.character),
          offsetOf(d.endLine, d.endCharacter),
          isError: d.isError,
        ),
    ];
  }

  /// Moves the cursor to the start of [line] (1-based), so tapping a finding shows it.
  void _jumpTo(int line) {
    var offset = 0;
    var current = 1;
    final text = _text.text;
    while (current < line && offset < text.length) {
      if (text.codeUnitAt(offset) == 10) {
        current++;
      }
      offset++;
    }
    _text.selection = TextSelection.collapsed(offset: offset);
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

  /// The live list under the cursor: keywords and project names matching the word
  /// being typed. The selected row is highlighted; a click accepts a row.
  Widget _completionList(List<CompletionItem> items) {
    final theme = Theme.of(context);
    final index = _completionIndex.clamp(0, items.length - 1);
    return Container(
      key: const Key('completion-list'),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (var i = 0; i < items.length && i < 30; i++)
            ListTile(
              key: Key('completion-${items[i].name}'),
              dense: true,
              selected: i == index,
              title: Text(
                items[i].name,
                style: const TextStyle(fontFamily: 'Menlo'),
              ),
              trailing: Text(items[i].kind, style: theme.textTheme.bodySmall),
              onTap: () => _complete(items[i].name),
            ),
        ],
      ),
    );
  }

  /// The analyzer's findings for this file, or a clean message. Tapping a finding
  /// moves the cursor to its line.
  Widget _analysisPanel(BuildContext context) {
    final live = _live ?? const <LiveDiagnostic>[];
    final issues = _issues ?? const <AnalysisIssue>[];
    if (issues.isEmpty && live.isNotEmpty) {
      return _liveList(context, live);
    }
    final theme = Theme.of(context);
    return Container(
      key: const Key('analysis-panel'),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: issues.isEmpty
          ? const ListTile(
              dense: true,
              title: Text('No problems in this file.'),
            )
          : ListView(
              shrinkWrap: true,
              children: [
                for (final issue in issues)
                  ListTile(
                    dense: true,
                    key: Key('finding-${issue.line}-${issue.column}'),
                    leading: Icon(
                      issue.severity == AnalysisSeverity.error
                          ? Icons.error_outline
                          : Icons.warning_amber_outlined,
                      color: issue.severity == AnalysisSeverity.error
                          ? theme.colorScheme.error
                          : theme.colorScheme.tertiary,
                    ),
                    title: Text(
                      '${issue.line}:${issue.column}  ${issue.message}',
                    ),
                    subtitle: Text(issue.code),
                    onTap: () => _jumpTo(issue.line),
                  ),
              ],
            ),
    );
  }

  /// The hover card: the symbol's description, with a close button.
  Widget _hoverCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('hover-card'),
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 160),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                _hover!,
                style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
              ),
            ),
          ),
          IconButton(
            key: const Key('hover-close'),
            tooltip: 'Close',
            iconSize: 16,
            onPressed: () => setState(() => _hover = null),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  /// The server's live problems for this file, as the file changes.
  Widget _liveList(BuildContext context, List<LiveDiagnostic> live) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('live-problems'),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final d in live)
            ListTile(
              dense: true,
              key: Key('live-${d.line}-${d.character}'),
              leading: Icon(
                d.isError ? Icons.error_outline : Icons.warning_amber_outlined,
                color: d.isError
                    ? theme.colorScheme.error
                    : theme.colorScheme.tertiary,
              ),
              title: Text('${d.line + 1}:${d.character + 1}  ${d.message}'),
              onTap: () => _jumpToPosition(d.line, d.character),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = p.basename(widget.filePath);
    final suggestions = _completionItems();
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
            if (widget.projectRoot != null)
              IconButton(
                key: const Key('code-analyze'),
                tooltip: 'Analyze project (compile check)',
                onPressed: _analyzing ? null : _analyze,
                icon: _analyzing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check_outlined),
              ),
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
            if (suggestions.isNotEmpty) _completionList(suggestions),
            Expanded(
              child: Focus(
                focusNode: _editorFocus,
                onKeyEvent: _onEditorKey,
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
            ),
            if (_hover != null) _hoverCard(context),
            if (_issues != null || (_live?.isNotEmpty ?? false))
              _analysisPanel(context),
          ],
        ),
      ),
    );
  }
}
