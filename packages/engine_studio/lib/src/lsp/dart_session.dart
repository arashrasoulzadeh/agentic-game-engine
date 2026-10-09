import 'dart:io';

import 'package:path/path.dart' as p;

import 'dart:async';

import 'edits.dart';
import 'lsp_client.dart';
import 'sdk_locator.dart';

/// One completion the language server offers: the text to insert, and its kind.
class ServerCompletion {
  /// What the designer sees in the list, such as `jump()`.
  final String label;

  /// The text to insert, such as `jump`. It differs from [label] for methods, whose
  /// label shows the parentheses.
  final String insertText;
  final String kind;
  final String? detail;

  const ServerCompletion(this.label, this.insertText, this.kind, {this.detail});
}

/// A running Dart analysis session for one project: the language server, with the
/// project's files open in it. Completions, diagnostics, and hover come from here.
class DartSession {
  final LspClient _client;
  final String projectRoot;
  final Map<String, int> _versions = {};

  DartSession._(this._client, this.projectRoot);

  /// Starts the server for [projectRoot] and completes the protocol handshake.
  static Future<DartSession> open(String projectRoot, {String? dart}) async {
    final binary = dart ?? findDartBinary();
    if (binary == null) {
      throw StateError('No Dart SDK found. Set DART_SDK or install Flutter.');
    }
    final client = await LspClient.start(
      dart: binary,
      projectRoot: projectRoot,
    );
    await client.request('initialize', {
      'processId': pid,
      'rootUri': Uri.directory(projectRoot).toString(),
      'capabilities': <String, dynamic>{},
      'workspaceFolders': [
        {
          'uri': Uri.directory(projectRoot).toString(),
          'name': p.basename(projectRoot),
        },
      ],
    });
    client.notify('initialized', {});
    return DartSession._(client, projectRoot);
  }

  String _uri(String path) => Uri.file(path).toString();

  /// Tells the server a file is open with [text]. Call once per file, before asking
  /// for completions in it.
  void openFile(String path, String text) {
    _versions[path] = 1;
    _client.notify('textDocument/didOpen', {
      'textDocument': {
        'uri': _uri(path),
        'languageId': 'dart',
        'version': 1,
        'text': text,
      },
    });
  }

  /// Sends the file's full current text after an edit.
  void change(String path, String text) {
    final version = (_versions[path] ?? 0) + 1;
    _versions[path] = version;
    _client.notify('textDocument/didChange', {
      'textDocument': {'uri': _uri(path), 'version': version},
      'contentChanges': [
        {'text': text},
      ],
    });
  }

  /// Completions at [line] and [character] (both 0-based) in the file at [path].
  Future<List<ServerCompletion>> completionsAt(
    String path,
    int line,
    int character,
  ) async {
    final result = await _client.request('textDocument/completion', {
      'textDocument': {'uri': _uri(path)},
      'position': {'line': line, 'character': character},
    });
    final items = result is Map ? result['items'] : result;
    if (items is! List) return const [];
    return [
      for (final item in items.cast<Map<String, dynamic>>())
        ServerCompletion(
          item['label'] as String,
          (item['insertText'] as String?) ??
              _insertFromLabel(item['label'] as String),
          _kindName(item['kind'] as int?),
          detail: item['detail'] as String?,
        ),
    ];
  }

  /// The edits needed to rename the symbol at [line] and [character] to [newName],
  /// grouped by file path. Empty when the server has nothing to rename there.
  Future<Map<String, List<TextEdit>>> renameAt(
    String path,
    int line,
    int character,
    String newName,
  ) async {
    final result = await _client.request('textDocument/rename', {
      'textDocument': {'uri': _uri(path)},
      'position': {'line': line, 'character': character},
      'newName': newName,
    });
    return parseWorkspaceEdit(result);
  }

  /// Every place the symbol at [line] and [character] is used, including its
  /// declaration. Each result is a file and the position in it.
  Future<List<SourceLocation>> referencesAt(
    String path,
    int line,
    int character,
  ) async {
    final result = await _client.request('textDocument/references', {
      'textDocument': {'uri': _uri(path)},
      'position': {'line': line, 'character': character},
      'context': {'includeDeclaration': true},
    });
    if (result is! List) return const [];
    return [
      for (final item in result.cast<Map<String, dynamic>>())
        SourceLocation(
          Uri.parse(item['uri'] as String).toFilePath(),
          (item['range']['start']['line'] as int),
          (item['range']['start']['character'] as int),
        ),
    ];
  }

  /// The documentation and type the server knows for the symbol at [line] and
  /// [character], as plain text, or null when there is nothing to show.
  Future<String?> hoverAt(String path, int line, int character) async {
    final result = await _client.request('textDocument/hover', {
      'textDocument': {'uri': _uri(path)},
      'position': {'line': line, 'character': character},
    });
    if (result is! Map) return null;
    return hoverText(result['contents']);
  }

  /// Problems the server reports for [path] as it analyzes, live. Each event is the
  /// full current list for the file, so an empty list means the file is clean now.
  Stream<List<LiveDiagnostic>> diagnosticsFor(String path) {
    final uri = _uri(path);
    return _client.notifications
        .where((m) => m['method'] == 'textDocument/publishDiagnostics')
        .map((m) => m['params'] as Map<String, dynamic>)
        .where((params) => params['uri'] == uri)
        .map(
          (params) => [
            for (final d
                in (params['diagnostics'] as List).cast<Map<String, dynamic>>())
              LiveDiagnostic.fromJson(d),
          ],
        );
  }

  /// Where the symbol at [line] and [character] in [path] is declared, or null when
  /// the server does not know.
  Future<SourceLocation?> definitionAt(
    String path,
    int line,
    int character,
  ) async {
    final result = await _client.request('textDocument/definition', {
      'textDocument': {'uri': _uri(path)},
      'position': {'line': line, 'character': character},
    });
    final first = result is List && result.isNotEmpty ? result.first : result;
    if (first is! Map<String, dynamic>) return null;
    final range = (first['range'] as Map).cast<String, dynamic>();
    final start = (range['start'] as Map).cast<String, dynamic>();
    return SourceLocation(
      Uri.parse(first['uri'] as String).toFilePath(),
      start['line'] as int,
      start['character'] as int,
    );
  }

  /// The formatted text of [path], as the server's formatter would write it, or null
  /// when there is nothing to change.
  Future<String?> formatted(String path, String text) async {
    final result = await _client.request('textDocument/formatting', {
      'textDocument': {'uri': _uri(path)},
      'options': {'tabSize': 2, 'insertSpaces': true},
    });
    if (result is! List || result.isEmpty) return null;
    final edits = [
      for (final e in result.cast<Map<String, dynamic>>())
        TextEdit(
          (e['range']['start']['line'] as int),
          (e['range']['start']['character'] as int),
          (e['range']['end']['line'] as int),
          (e['range']['end']['character'] as int),
          e['newText'] as String,
        ),
    ];
    return applyEdits(text, edits);
  }

  /// Ends the session: asks the server to shut down, then exits it.
  Future<void> close() async {
    await _client.request('shutdown', {});
    _client.notify('exit', {});
    await _client.dispose();
  }
}

/// The text to insert for a label that has no explicit insert text: the name before
/// any parameter list, so `jump()` inserts `jump`.
String _insertFromLabel(String label) {
  final paren = label.indexOf('(');
  return paren < 0 ? label : label.substring(0, paren);
}

/// The name for an LSP CompletionItemKind number, as the server reports it.
String _kindName(int? kind) => switch (kind) {
  2 => 'method',
  3 => 'function',
  4 => 'constructor',
  5 => 'field',
  6 => 'variable',
  7 => 'class',
  8 => 'interface',
  9 => 'module',
  10 => 'property',
  13 => 'enum',
  14 => 'keyword',
  21 => 'constant',
  _ => 'symbol',
};

/// A place in a file: where a definition is.
class SourceLocation {
  final String path;
  final int line;
  final int character;

  const SourceLocation(this.path, this.line, this.character);
}

/// One problem the server reports as it analyzes: its severity, place, and message.
class LiveDiagnostic {
  final int line;
  final int character;

  /// Where the problem ends, so the editor can underline exactly the bad text.
  final int endLine;
  final int endCharacter;
  final int severity;
  final String message;
  final String? code;

  const LiveDiagnostic({
    required this.line,
    required this.character,
    required this.endLine,
    required this.endCharacter,
    required this.severity,
    required this.message,
    this.code,
  });

  /// LSP severities: 1 error, 2 warning, 3 information, 4 hint.
  bool get isError => severity == 1;

  factory LiveDiagnostic.fromJson(Map<String, dynamic> json) {
    final range = (json['range'] as Map).cast<String, dynamic>();
    final start = (range['start'] as Map).cast<String, dynamic>();
    final end = (range['end'] as Map).cast<String, dynamic>();
    return LiveDiagnostic(
      line: start['line'] as int,
      character: start['character'] as int,
      endLine: end['line'] as int,
      endCharacter: end['character'] as int,
      severity: (json['severity'] as int?) ?? 1,
      message: json['message'] as String,
      code: json['code']?.toString(),
    );
  }
}

/// Turns hover contents into plain text. The protocol allows markup, a plain string,
/// a list of either, or a marked string with a language; all of them reduce to the
/// text a designer reads. Blank contents give null.
String? hoverText(Object? contents) {
  final text = switch (contents) {
    String value => value,
    Map value when value['value'] is String => value['value'] as String,
    List value => value.map(hoverText).whereType<String>().join('\n\n'),
    _ => null,
  };
  final trimmed = text?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Reads a `WorkspaceEdit` into edits grouped by file path. The protocol allows
/// either a `changes` map (uri to edits) or a `documentChanges` list of per-document
/// edits; both are read the same way here.
Map<String, List<TextEdit>> parseWorkspaceEdit(Object? result) {
  if (result is! Map) return const {};
  final grouped = <String, List<TextEdit>>{};

  void addEdits(String uri, List edits) {
    final path = Uri.parse(uri).toFilePath();
    grouped.putIfAbsent(path, () => []).addAll([
      for (final e in edits.cast<Map<String, dynamic>>())
        TextEdit(
          e['range']['start']['line'] as int,
          e['range']['start']['character'] as int,
          e['range']['end']['line'] as int,
          e['range']['end']['character'] as int,
          e['newText'] as String,
        ),
    ]);
  }

  final changes = result['changes'];
  if (changes is Map) {
    changes.forEach((uri, edits) => addEdits(uri as String, edits as List));
  }
  final documentChanges = result['documentChanges'];
  if (documentChanges is List) {
    for (final change in documentChanges.cast<Map<String, dynamic>>()) {
      final doc = change['textDocument'];
      if (doc is Map && doc['uri'] is String && change['edits'] is List) {
        addEdits(doc['uri'] as String, change['edits'] as List);
      }
    }
  }
  return grouped;
}
