import 'dart:io';

import 'package:path/path.dart' as p;

import 'lsp_client.dart';

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
  static Future<DartSession> open(
    String projectRoot, {
    String dart = 'dart',
  }) async {
    final client = await LspClient.start(dart: dart, projectRoot: projectRoot);
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
