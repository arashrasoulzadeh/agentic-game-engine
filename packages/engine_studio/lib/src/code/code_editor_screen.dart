import '../prefs/shortcuts.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'dart:async';

import '../lsp/dart_session.dart';
import '../lsp/edits.dart' show RenamePlan, TextEdit, applyEdits, planRename;
import 'analysis.dart';
import 'auto_close.dart';
import 'auto_indent.dart';
import 'editor_settings.dart';
import 'bracket_match.dart';
import 'completion.dart';
import 'dart_highlighter.dart';
import 'find_replace.dart';
import 'marks.dart';
import 'project_symbols.dart';
import '../prefs/strings.dart';
import 'folding.dart';

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

  /// Where the cursor starts, for opening a file at a result such as a reference.
  final int initialLine;
  final int initialCharacter;

  /// Fold regions to offer when there is no language server to ask (tests, offline use).
  final List<FoldingRange> staticFoldingRanges;

  const CodeEditorScreen({
    super.key,
    required this.filePath,
    this.projectRoot,
    this.analyzer,
    this.useLanguageServer = true,
    this.initialLine = 0,
    this.initialCharacter = 0,
    this.staticFoldingRanges = const [],
  });

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

/// The line height multiplier shared by the text field and the line-number
/// gutter so a line in one lines up with the same line in the other. Font
/// size itself is a per-project setting (see [EditorSettings]), not a
/// constant, so the gutter's line height is computed from it per instance.
const _editorLineHeightMultiplier = 1.4;

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  late final TextEditingController _text;
  // Two separate controllers, not one shared: a ScrollController can only ever
  // attach to a single scroll view, so the text field's own scrolling is
  // mirrored onto the gutter's by hand instead (see _syncGutterScroll).
  final ScrollController _editorScroll = ScrollController();
  final ScrollController _gutterScroll = ScrollController();
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
  List<SourceLocation>? _references;
  List<DocumentSymbolEntry>? _outline;
  late List<FoldingRange> _foldingRanges = widget.staticFoldingRanges;

  /// Start lines of the folds currently collapsed, and the text they were collapsed against. A fold is a
  /// view over the text as it was when the ranges were computed, so any edit expands them all again.
  final Set<int> _collapsed = {};
  String _foldedText = '';
  List<CodeActionItem>? _quickFixes;
  int _quickFixRequest = 0;
  List<CompletionItem>? _serverItems;
  int _serverRequest = 0;
  bool _analyzing = false;
  bool _findOpen = false;
  bool _replaceOpen = false;
  int _matchIndex = 0;
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final FocusNode _findFocus = FocusNode();

  /// The buffer's text right before the latest keystroke, so [_maybeAutoClose]
  /// can tell a single typed character apart from a paste or a programmatic
  /// edit (format, rename, completion), which must never be auto-closed.
  late String _previousText;

  EditorSettings _settings = const EditorSettings();
  EditorSettingsStore? _settingsStore;

  double get _fontSize => _settings.fontSize;
  double get _lineHeight => _fontSize * _editorLineHeightMultiplier;
  String get _indentUnit => ' ' * _settings.tabWidth;

  bool get _isDart => widget.filePath.endsWith('.dart');

  @override
  void initState() {
    super.initState();
    _saved = File(widget.filePath).readAsStringSync();
    _previousText = _saved;
    _text = _isDart
        ? DartHighlightController(text: _saved)
        : TextEditingController(text: _saved);
    _text.addListener(_onTextChanged);
    _editorScroll.addListener(_syncGutterScroll);
    if (widget.initialLine > 0 || widget.initialCharacter > 0) {
      final start = _offsetOf(widget.initialLine, widget.initialCharacter);
      _text.selection = TextSelection.collapsed(offset: start);
    }
    final root = widget.projectRoot;
    if (root != null) {
      _settingsStore = EditorSettingsStore(root);
      _settings = _settingsStore!.read();
    }
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
      final ranges = await session.foldingRanges(widget.filePath);
      if (mounted) setState(() => _foldingRanges = ranges);
    } on Object {
      // Fall back to the local list; the editor works without the server.
    }
  }

  void _onTextChanged() {
    _syncFolds();
    _session?.change(widget.filePath, _text.text);
    _scheduleFoldRefresh();
    setState(() {
      _completionIndex = 0;
      _completionDismissed = false;
      _serverItems = null;
    });
    _requestServerCompletions();
    _updateSearchHighlights();
    _updateBracketHighlight();
    _maybeAutoClose();
  }

  /// Keeps the folds honest: an edit invalidates every fold (their line numbers describe the old text), and a
  /// caret that lands inside hidden text opens the fold it is in, since the player could not see what they
  /// were typing into.
  void _syncFolds() {
    if (_collapsed.isEmpty) return;
    if (_text.text != _foldedText) {
      _collapsed.clear();
      _applyFolds();
      return;
    }
    final hidden = hiddenRangesFor(_text.text, _foldingRanges, _collapsed);
    final caret = _text.selection.baseOffset;
    if (caret < 0 || !insideHidden(hidden, caret)) return;
    final line = '\n'.allMatches(_text.text.substring(0, caret)).length;
    _collapsed.removeWhere((start) {
      final r = _foldingRanges.firstWhere((r) => r.startLine == start);
      return line > r.startLine && line <= r.endLine;
    });
    _applyFolds();
  }

  Timer? _foldRefresh;

  /// Asks the server for fresh fold regions shortly after typing stops, so the indicators describe the text
  /// as it is now (the ones from before the edit point at the wrong lines).
  void _scheduleFoldRefresh() {
    final session = _session;
    if (session == null) return;
    _foldRefresh?.cancel();
    _foldRefresh = Timer(const Duration(milliseconds: 600), () async {
      try {
        final ranges = await session.foldingRanges(widget.filePath);
        if (mounted) setState(() => _foldingRanges = ranges);
      } on Object {
        // Keep the old indicators; the next edit retries.
      }
    });
  }

  /// Pushes the collapsed folds to the highlighter (non-Dart files have no folding).
  void _applyFolds() {
    final highlighter = _text;
    _foldedText = _text.text;
    if (highlighter is DartHighlightController) {
      highlighter.folded = hiddenRangesFor(
        _text.text,
        _foldingRanges,
        _collapsed,
      );
    }
  }

  /// Collapses or expands the fold that starts on [line].
  void _toggleFold(int line) {
    setState(() {
      if (!_collapsed.remove(line)) _collapsed.add(line);
      _applyFolds();
    });
  }

  /// Auto-closes a bracket or quote just typed, or types through one already
  /// auto-closed, by diffing against [_previousText] (see [autoCloseResult]).
  /// Mutating `_text.value` here re-enters this listener once more, but with
  /// [_previousText] already updated to match, so that nested call's own diff
  /// finds nothing to do and the recursion stops there.
  void _maybeAutoClose() {
    final previous = _previousText;
    final cursor = _text.selection.baseOffset;
    _previousText = _text.text;
    if (cursor < 0) return;
    final result = autoCloseResult(previous, _text.text, cursor);
    if (result == null) return;
    final (newText, newCursor) = result;
    _previousText = newText;
    _text.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  /// Replaces a default Enter with one that matches the current line's
  /// indentation (see [indentedNewline]).
  void _insertIndentedNewline() {
    final cursor = _text.selection.baseOffset.clamp(0, _text.text.length);
    final (newText, newCursor) = indentedNewline(
      _text.text,
      cursor,
      indentUnit: _indentUnit,
    );
    _text.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  /// Highlights the bracket at the cursor and the one it pairs with. Does
  /// nothing for a non-Dart file, which has no highlighter to mark.
  void _updateBracketHighlight() {
    final highlighter = _text;
    if (highlighter is! DartHighlightController) return;
    final cursor = _text.selection.baseOffset;
    if (cursor < 0) {
      highlighter.bracketMarks = const [];
      return;
    }
    final found = matchingBracket(_text.text, cursor);
    if (found == null) {
      highlighter.bracketMarks = const [];
      return;
    }
    final (at, pair) = found;
    highlighter.bracketMarks = [
      TextMark(at, at + 1, kind: MarkKind.bracket),
      TextMark(pair, pair + 1, kind: MarkKind.bracket),
    ];
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
          for (final item in items)
            CompletionItem(
              item.insertText,
              item.kind,
              label: item.label,
              detail: item.detail,
            ),
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
    _foldRefresh?.cancel();
    _text.removeListener(_onTextChanged);
    _text.dispose();
    _editorFocus.dispose();
    _findController.dispose();
    _replaceController.dispose();
    _findFocus.dispose();
    _editorScroll.removeListener(_syncGutterScroll);
    _editorScroll.dispose();
    _gutterScroll.dispose();
    super.dispose();
  }

  /// Mirrors the text field's scroll offset onto the gutter's own controller,
  /// clamped to what the gutter can actually scroll (it may be shorter or
  /// taller than the text field by a line or two).
  void _syncGutterScroll() {
    if (!_editorScroll.hasClients || !_gutterScroll.hasClients) return;
    final max = _gutterScroll.position.maxScrollExtent;
    _gutterScroll.jumpTo(_editorScroll.offset.clamp(0, max));
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
      if (keyboard.isShiftPressed &&
          event.logicalKey == LogicalKeyboardKey.f12) {
        _showReferences();
        return KeyEventResult.handled;
      }
      if (!keyboard.isShiftPressed &&
          event.logicalKey == LogicalKeyboardKey.f2) {
        _renameSymbol();
        return KeyEventResult.handled;
      }
      if (command && event.logicalKey == LogicalKeyboardKey.keyK) {
        _showHover();
        return KeyEventResult.handled;
      }
      if (command && event.logicalKey == LogicalKeyboardKey.period) {
        _showQuickFixes();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyF &&
          keyboard.isAltPressed &&
          keyboard.isShiftPressed) {
        _format();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter &&
          !command &&
          !keyboard.isShiftPressed &&
          _completionItems().isEmpty) {
        _insertIndentedNewline();
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
      return _rankedByMatch(server, word);
    }
    return completionsFor(word, _symbols);
  }

  /// The items matching [word], case-insensitively, ranked the way an IDE's list
  /// is: a name that starts with what was typed comes before one that merely
  /// contains it, and among ties the shorter (closer) name comes first.
  List<CompletionItem> _rankedByMatch(List<CompletionItem> items, String word) {
    final needle = word.toLowerCase();
    final matches = [
      for (final item in items)
        if (item.name.toLowerCase().contains(needle)) item,
    ];
    matches.sort((a, b) {
      final aStarts = a.name.toLowerCase().startsWith(needle);
      final bStarts = b.name.toLowerCase().startsWith(needle);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return a.name.length.compareTo(b.name.length);
    });
    return matches;
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

  /// The identifier touching the cursor: the letters/digits/underscore run the
  /// cursor is inside or right after. Used to prefill the rename dialog.
  String _identifierAtCursor() {
    final offset = _text.selection.baseOffset.clamp(0, _text.text.length);
    final text = _text.text;
    var start = offset;
    while (start > 0 && RegExp(r'\w').hasMatch(text[start - 1])) {
      start--;
    }
    var end = offset;
    while (end < text.length && RegExp(r'\w').hasMatch(text[end])) {
      end++;
    }
    return text.substring(start, end);
  }

  /// Renames the symbol at the cursor: asks for the new name, applies the server's
  /// edits to this buffer (undoable, unsaved until the file is saved), and asks
  /// before writing the edits in other files to disk.
  Future<void> _renameSymbol() async {
    final session = _session;
    if (session == null) return;
    final current = _identifierAtCursor();
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initialName: current),
    );
    if (newName == null || newName.isEmpty || newName == current || !mounted) {
      return;
    }

    final (line, character) = _cursorPosition();
    Map<String, List<TextEdit>> grouped;
    try {
      grouped = await session.renameAt(
        widget.filePath,
        line,
        character,
        newName,
      );
    } on Object {
      return;
    }
    if (!mounted || grouped.isEmpty) return;
    final plan = planRename(grouped, widget.filePath, _text.text);

    if (plan.currentFileText != null) {
      _text.value = TextEditingValue(text: plan.currentFileText!);
    }
    if (plan.otherFiles.isNotEmpty) {
      await _confirmAndWriteOthers(plan);
    }
  }

  /// Shows the files a rename would also change and writes them on confirmation.
  Future<void> _confirmAndWriteOthers(RenamePlan plan) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(StudioStrings.t('code.renameOthersTitle')),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final path in plan.otherFiles.keys)
                    Text(
                      p.basename(path),
                      key: Key('rename-file-${p.basename(path)}'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(StudioStrings.t('common.cancel')),
              ),
              FilledButton(
                key: const Key('rename-apply'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(StudioStrings.t('code.apply')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    for (final entry in plan.otherFiles.entries) {
      final file = File(entry.key);
      if (!file.existsSync()) continue;
      final updated = applyEdits(file.readAsStringSync(), entry.value);
      final temp = File('${entry.key}.tmp')
        ..writeAsStringSync(updated, flush: true);
      temp.renameSync(entry.key);
    }
  }

  /// Lists every use of the symbol at the cursor, across the project. Tapping one
  /// opens its file at that line.
  Future<void> _showReferences() async {
    final session = _session;
    if (session == null) return;
    final (line, character) = _cursorPosition();
    final found = await session.referencesAt(widget.filePath, line, character);
    if (!mounted) return;
    setState(() => _references = found);
  }

  /// Lists the file's classes/methods/fields. Tapping one moves the cursor
  /// there. Toggling it closed again when it's already open, rather than
  /// re-requesting it, matches how the hover/references/quick-fix panels
  /// each already behave.
  Future<void> _toggleOutline() async {
    if (_outline != null) {
      setState(() => _outline = null);
      return;
    }
    final session = _session;
    if (session == null) return;
    final found = await session.documentSymbols(widget.filePath);
    if (!mounted) return;
    setState(() => _outline = found);
  }

  void _openReference(SourceLocation at) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CodeEditorScreen(
          filePath: at.path,
          projectRoot: widget.projectRoot,
          analyzer: widget.analyzer,
          useLanguageServer: widget.useLanguageServer,
          initialLine: at.line,
          initialCharacter: at.character,
        ),
      ),
    );
  }

  /// Lists the analyzer's fixes for the cursor's line: both quick fixes for a
  /// problem there and refactoring assists. The nearby diagnostics are sent as
  /// context, which is how the server matches a fix to the right problem.
  Future<void> _showQuickFixes() async {
    final session = _session;
    if (session == null) return;
    final request = ++_quickFixRequest;
    final (line, character) = _cursorPosition();
    final diagnostics = session
        .rawDiagnosticsFor(widget.filePath)
        .where((d) => (d['range']['start']['line'] as int) == line)
        .toList();
    final found = await session.codeActionsAt(
      widget.filePath,
      line,
      character,
      diagnosticsJson: diagnostics,
    );
    if (!mounted || request != _quickFixRequest) return;
    setState(() => _quickFixes = found.isEmpty ? null : found);
  }

  /// Runs a quick fix: applies it to this buffer if it touches this file, and asks
  /// before writing any edits it makes in other files.
  Future<void> _applyQuickFix(CodeActionItem item) async {
    final session = _session;
    if (session == null) return;
    setState(() => _quickFixes = null);
    final grouped = await session.applyCodeAction(item);
    if (!mounted || grouped.isEmpty) return;
    final plan = planRename(grouped, widget.filePath, _text.text);
    if (plan.currentFileText != null) {
      _text.value = TextEditingValue(text: plan.currentFileText!);
    }
    if (plan.otherFiles.isNotEmpty) {
      await _confirmAndWriteOthers(plan);
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

  int _offsetOf(int line, int character) {
    var offset = 0;
    var current = 0;
    final text = _text.text;
    while (current < line && offset < text.length) {
      if (text.codeUnitAt(offset) == 10) current++;
      offset++;
    }
    return (offset + character).clamp(0, text.length);
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
      await _save();
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
          kind: d.isError ? MarkKind.error : MarkKind.warning,
        ),
    ];
  }

  /// The find bar's matches in the current text, recomputed from the query.
  List<TextMatch> get _matches => findMatches(_text.text, _findController.text);

  /// Opens the find bar (Cmd/Ctrl+F), or just focuses it if already open.
  void _openFind() {
    setState(() {
      _findOpen = true;
      _matchIndex = 0;
    });
    _findFocus.requestFocus();
    _updateSearchHighlights();
  }

  /// Opens the find bar with its replace row (Cmd/Ctrl+H).
  void _openReplace() {
    setState(() {
      _findOpen = true;
      _replaceOpen = true;
      _matchIndex = 0;
    });
    _findFocus.requestFocus();
    _updateSearchHighlights();
  }

  /// Closes the find bar and clears its highlights.
  void _closeFind() {
    setState(() {
      _findOpen = false;
      _replaceOpen = false;
    });
    _updateSearchHighlights();
    _editorFocus.requestFocus();
  }

  /// Selects the next match, wrapping to the first after the last.
  void _nextMatch() {
    final matches = _matches;
    if (matches.isEmpty) return;
    setState(() => _matchIndex = (_matchIndex + 1) % matches.length);
    _selectCurrentMatch();
  }

  /// Selects the previous match, wrapping to the last before the first.
  void _previousMatch() {
    final matches = _matches;
    if (matches.isEmpty) return;
    setState(
      () => _matchIndex = (_matchIndex - 1 + matches.length) % matches.length,
    );
    _selectCurrentMatch();
  }

  void _selectCurrentMatch() {
    final matches = _matches;
    if (matches.isEmpty) return;
    final match = matches[_matchIndex.clamp(0, matches.length - 1)];
    _text.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
    _updateSearchHighlights();
  }

  /// Replaces the current match and moves on to the next one.
  void _replaceCurrent() {
    final matches = _matches;
    if (matches.isEmpty) return;
    final match = matches[_matchIndex.clamp(0, matches.length - 1)];
    final replacement = _replaceController.text;
    final updated = _text.text.replaceRange(
      match.start,
      match.end,
      replacement,
    );
    _text.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset: match.start + replacement.length,
      ),
    );
  }

  /// Replaces every match in the file in one edit.
  void _replaceAll() {
    final updated = replaceAllMatches(
      _text.text,
      _findController.text,
      _replaceController.text,
    );
    _text.value = TextEditingValue(
      text: updated,
      selection: const TextSelection.collapsed(offset: 0),
    );
    setState(() => _matchIndex = 0);
  }

  /// Marks every match in the Dart highlighter, with the current one brighter.
  /// Does nothing for a non-Dart file, which has no highlighter to mark.
  void _updateSearchHighlights() {
    final highlighter = _text;
    if (highlighter is! DartHighlightController) return;
    if (!_findOpen || _findController.text.isEmpty) {
      highlighter.searchMarks = const [];
      return;
    }
    final matches = _matches;
    final current = _matchIndex.clamp(
      0,
      matches.isEmpty ? 0 : matches.length - 1,
    );
    highlighter.searchMarks = [
      for (var i = 0; i < matches.length; i++)
        TextMark(
          matches[i].start,
          matches[i].end,
          kind: i == current ? MarkKind.currentMatch : MarkKind.searchMatch,
        ),
    ];
  }

  /// Handles keys inside the find field: Escape closes the bar, Shift+Enter
  /// goes to the previous match (plain Enter goes to the next, via onSubmitted).
  KeyEventResult _onFindKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _closeFind();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter &&
          HardwareKeyboard.instance.isShiftPressed) {
        _previousMatch();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
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

  Future<void> _save() async {
    if (!_dirty) {
      return;
    }
    if (_settings.formatOnSave) {
      await _format();
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

  /// Opens the editor settings dialog and saves whatever comes back.
  Future<void> _showSettings() async {
    final store = _settingsStore;
    if (store == null) return;
    final updated = await showDialog<EditorSettings>(
      context: context,
      builder: (context) => _EditorSettingsDialog(initial: _settings),
    );
    if (updated == null || !mounted) return;
    store.write(updated);
    setState(() => _settings = updated);
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
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      // A Material (not a decorated Container) paints the background so the
      // ListTiles' selection and ink effects are visible on top of it.
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < items.length && i < 30; i++)
              ListTile(
                key: Key('completion-${items[i].name}'),
                dense: true,
                selected: i == index,
                leading: Icon(iconForCompletionKind(items[i].kind), size: 16),
                title: Text(
                  items[i].label,
                  style: const TextStyle(fontFamily: 'Menlo'),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    items[i].detail ?? items[i].kind,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
                onTap: () => _complete(items[i].name),
              ),
          ],
        ),
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
          ? ListTile(
              dense: true,
              title: Text(StudioStrings.t('code.noProblems')),
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

  /// The references list: each use of the symbol, with its file and line.
  Widget _referencesPanel(BuildContext context) {
    final theme = Theme.of(context);
    final found = _references!;
    return Container(
      key: const Key('references-panel'),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    StudioStrings.t('code.references', {'count': found.length}),
                  ),
                ),
              ),
              IconButton(
                key: const Key('references-close'),
                tooltip: StudioStrings.t('common.close'),
                iconSize: 16,
                onPressed: () => setState(() => _references = null),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final at in found)
                  ListTile(
                    dense: true,
                    key: Key('reference-${at.path}-${at.line}-${at.character}'),
                    title: Text(
                      '${p.basename(at.path)}:${at.line + 1}:${at.character + 1}',
                    ),
                    subtitle: Text(at.path, overflow: TextOverflow.ellipsis),
                    onTap: () => _openReference(at),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The file's outline: one row per class/method/field, indented by
  /// nesting depth. Tapping a row moves the cursor there.
  Widget _outlinePanel(BuildContext context) {
    final theme = Theme.of(context);
    final found = _outline!;
    return Container(
      key: const Key('outline-panel'),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    found.isEmpty
                        ? 'No symbols found'
                        : '${found.length} symbol(s)',
                  ),
                ),
              ),
              IconButton(
                key: const Key('outline-close'),
                tooltip: StudioStrings.t('common.close'),
                iconSize: 16,
                onPressed: () => setState(() => _outline = null),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final symbol in found)
                  ListTile(
                    dense: true,
                    key: Key(
                      'outline-${symbol.name}-${symbol.line}-${symbol.character}',
                    ),
                    contentPadding: EdgeInsets.only(
                      left: 16.0 + symbol.depth * 16,
                      right: 16,
                    ),
                    leading: Icon(iconForCompletionKind(symbol.kind), size: 16),
                    title: Text(
                      symbol.name,
                      style: const TextStyle(fontFamily: 'Menlo'),
                    ),
                    trailing: Text(
                      symbol.kind,
                      style: theme.textTheme.bodySmall,
                    ),
                    onTap: () {
                      setState(() => _outline = null);
                      _jumpToPosition(symbol.line, symbol.character);
                      _editorFocus.requestFocus();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The quick-fix list for the cursor's line. Tapping one applies it.
  Widget _quickFixesPanel(BuildContext context) {
    final theme = Theme.of(context);
    final found = _quickFixes!;
    return Container(
      key: const Key('quick-fixes-panel'),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    StudioStrings.t('code.fixes', {'count': found.length}),
                  ),
                ),
              ),
              IconButton(
                key: const Key('quick-fixes-close'),
                tooltip: StudioStrings.t('common.close'),
                iconSize: 16,
                onPressed: () => setState(() => _quickFixes = null),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final item in found)
                  ListTile(
                    dense: true,
                    key: Key('quick-fix-${item.title}'),
                    leading: const Icon(Icons.lightbulb_outline),
                    title: Text(item.title),
                    onTap: () => _applyQuickFix(item),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The line-number gutter: one number per line, the current line highlighted.
  /// It scrolls with the text field via the shared [_editorScroll] controller,
  /// and each number sits in a fixed-height box matching the text field's own
  /// line height, so the two stay lined up.
  Widget _gutter(BuildContext context) {
    final theme = Theme.of(context);
    final lineCount = '\n'.allMatches(_text.text).length + 1;
    final currentLine = _cursorPosition().$1;
    final digits = '$lineCount'.length;
    final foldStarts = {for (final r in _foldingRanges) r.startLine: r};
    final hasFolds = foldStarts.isNotEmpty;
    final hiddenLines = hiddenLinesFor(_foldingRanges, _collapsed);
    return Container(
      key: const Key('editor-gutter'),
      width: 24.0 + digits * 8.0 + (hasFolds ? 16 : 0),
      color: theme.colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        controller: _gutterScroll,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var line = 0; line < lineCount; line++)
              if (!hiddenLines.contains(line))
                Container(
                  key: Key('gutter-line-${line + 1}'),
                  height: _lineHeight,
                  width: double.infinity,
                  padding: const EdgeInsets.only(right: 8),
                  color: line == currentLine
                      ? theme.colorScheme.surfaceContainerHigh
                      : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (hasFolds)
                        SizedBox(
                          width: 16,
                          height: _lineHeight,
                          child: foldStarts.containsKey(line)
                              ? InkWell(
                                  key: Key('fold-$line'),
                                  onTap: () => _toggleFold(line),
                                  child: Icon(
                                    _collapsed.contains(line)
                                        ? Icons.chevron_right
                                        : Icons.expand_more,
                                    size: 12,
                                    semanticLabel: _collapsed.contains(line)
                                        ? 'Expand'
                                        : 'Collapse',
                                  ),
                                )
                              : null,
                        ),
                      Text(
                        '${line + 1}',
                        style: TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: _fontSize,
                          height: _editorLineHeightMultiplier,
                          color: line == currentLine
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// The find bar: a query field with a match count and next/previous, plus a
  /// replace row when opened with Cmd/Ctrl+H.
  Widget _findBar(BuildContext context) {
    final theme = Theme.of(context);
    final matches = _matches;
    final count = matches.isEmpty
        ? '0/0'
        : '${_matchIndex.clamp(0, matches.length - 1) + 1}/${matches.length}';
    return Container(
      key: const Key('find-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Focus(
                  onKeyEvent: _onFindKey,
                  child: TextField(
                    key: const Key('find-input'),
                    controller: _findController,
                    focusNode: _findFocus,
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: StudioStrings.t('code.find'),
                    ),
                    onSubmitted: (_) => _nextMatch(),
                    onChanged: (_) {
                      setState(() => _matchIndex = 0);
                      _updateSearchHighlights();
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(count, key: const Key('find-count')),
              ),
              IconButton(
                key: const Key('find-prev'),
                tooltip: StudioStrings.t('code.prevMatch'),
                iconSize: 16,
                onPressed: _previousMatch,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                key: const Key('find-next'),
                tooltip: StudioStrings.t('code.nextMatch'),
                iconSize: 16,
                onPressed: _nextMatch,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
              IconButton(
                key: const Key('find-close'),
                tooltip: StudioStrings.t('code.closeFind'),
                iconSize: 16,
                onPressed: _closeFind,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (_replaceOpen)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('replace-input'),
                    controller: _replaceController,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: StudioStrings.t('code.replace'),
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('replace-one'),
                  onPressed: _replaceCurrent,
                  child: Text(StudioStrings.t('code.replace')),
                ),
                TextButton(
                  key: const Key('replace-all'),
                  onPressed: _replaceAll,
                  child: Text(StudioStrings.t('code.replaceAll')),
                ),
              ],
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
            tooltip: StudioStrings.t('common.close'),
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

  /// Asks before discarding unsaved changes, so closing a dirty file
  /// (popping this screen off the navigation stack — opened via go-to-
  /// definition or a project-search result) never silently loses an edit.
  /// A clean file pops immediately, with no dialog.
  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop) return;
    final discard =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(StudioStrings.t('code.discardTitle')),
            content: Text(
              '${p.basename(widget.filePath)} has unsaved changes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(StudioStrings.t('common.cancel')),
              ),
              FilledButton(
                key: const Key('discard-changes'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(StudioStrings.t('code.discard')),
              ),
            ],
          ),
        ) ??
        false;
    if (discard && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final name = p.basename(widget.filePath);
    final suggestions = _completionItems();
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: _onPopInvoked,
      child: CallbackShortcuts(
        bindings: ShortcutMap.current.bindings({
          StudioAction.save: _save,
          StudioAction.find: _openFind,
          StudioAction.replace: _openReplace,
        }),
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
              if (_session != null)
                IconButton(
                  key: const Key('code-outline'),
                  tooltip: StudioStrings.t('code.outline'),
                  onPressed: _toggleOutline,
                  icon: const Icon(Icons.list_alt_outlined),
                ),
              if (widget.projectRoot != null)
                IconButton(
                  key: const Key('code-analyze'),
                  tooltip: StudioStrings.t('code.analyze'),
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
                tooltip: StudioStrings.t('level.save'),
                onPressed: _dirty ? _save : null,
                icon: const Icon(Icons.save_outlined),
              ),
              if (widget.projectRoot != null)
                IconButton(
                  key: const Key('code-settings'),
                  tooltip: StudioStrings.t('code.settings'),
                  onPressed: _showSettings,
                  icon: const Icon(Icons.settings_outlined),
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (suggestions.isNotEmpty) _completionList(suggestions),
              if (_findOpen) _findBar(context),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _gutter(context),
                    Expanded(
                      child: Focus(
                        focusNode: _editorFocus,
                        onKeyEvent: _onEditorKey,
                        child: TextField(
                          key: const Key('code-text'),
                          controller: _text,
                          scrollController: _editorScroll,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          // A tiny strut so collapsed (near-zero-size) lines really shrink: the default
                          // strut would hold every line at full height.
                          strutStyle: const StrutStyle(
                            fontSize: 0.01,
                            height: 0.01,
                          ),
                          style: TextStyle(
                            fontFamily: 'Menlo',
                            fontSize: _fontSize,
                            height: _editorLineHeightMultiplier,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_hover != null) _hoverCard(context),
              if (_references != null) _referencesPanel(context),
              if (_outline != null) _outlinePanel(context),
              if (_quickFixes != null) _quickFixesPanel(context),
              if (_issues != null || (_live?.isNotEmpty ?? false))
                _analysisPanel(context),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the new name when renaming a symbol, prefilled with the current one.
class _RenameDialog extends StatefulWidget {
  final String initialName;

  const _RenameDialog({required this.initialName});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(StudioStrings.t('code.renameTitle')),
      content: TextField(
        key: const Key('rename-input'),
        controller: _controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(StudioStrings.t('common.cancel')),
        ),
        FilledButton(
          key: const Key('rename-confirm'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(StudioStrings.t('code.rename')),
        ),
      ],
    );
  }
}

/// Lets the designer change font size, tab width, and format-on-save
/// (docs/studio/design.md IDE.13). Returns the new settings on Save, or null if
/// cancelled.
class _EditorSettingsDialog extends StatefulWidget {
  final EditorSettings initial;

  const _EditorSettingsDialog({required this.initial});

  @override
  State<_EditorSettingsDialog> createState() => _EditorSettingsDialogState();
}

class _EditorSettingsDialogState extends State<_EditorSettingsDialog> {
  late double _fontSize;
  late int _tabWidth;
  late bool _formatOnSave;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.initial.fontSize;
    _tabWidth = widget.initial.tabWidth;
    _formatOnSave = widget.initial.formatOnSave;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(StudioStrings.t('code.settings')),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(StudioStrings.t('code.fontSize', {'size': _fontSize.round()})),
            Slider(
              key: const Key('settings-font-size'),
              value: _fontSize,
              min: 8,
              max: 32,
              divisions: 24,
              label: _fontSize.round().toString(),
              onChanged: (v) => setState(() => _fontSize = v),
            ),
            Text(StudioStrings.t('code.tabWidth', {'width': _tabWidth})),
            Slider(
              key: const Key('settings-tab-width'),
              value: _tabWidth.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              label: '$_tabWidth',
              onChanged: (v) => setState(() => _tabWidth = v.round()),
            ),
            SwitchListTile(
              key: const Key('settings-format-on-save'),
              contentPadding: EdgeInsets.zero,
              title: Text(StudioStrings.t('code.formatOnSave')),
              value: _formatOnSave,
              onChanged: (v) => setState(() => _formatOnSave = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(StudioStrings.t('common.cancel')),
        ),
        FilledButton(
          key: const Key('settings-save'),
          onPressed: () => Navigator.of(context).pop(
            EditorSettings(
              fontSize: _fontSize,
              tabWidth: _tabWidth,
              formatOnSave: _formatOnSave,
            ),
          ),
          child: Text(StudioStrings.t('graph.save')),
        ),
      ],
    );
  }
}
