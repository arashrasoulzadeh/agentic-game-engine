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

  final Map<String, List<Map<String, dynamic>>> _rawDiagnostics = {};
  final StreamController<Map<String, dynamic>> _appliedEdits =
      StreamController<Map<String, dynamic>>.broadcast();

  DartSession._(this._client, this.projectRoot) {
    _client.notifications
        .where((m) => m['method'] == 'textDocument/publishDiagnostics')
        .listen((m) {
          final params = m['params'] as Map<String, dynamic>;
          _rawDiagnostics[params['uri'] as String] =
              (params['diagnostics'] as List).cast<Map<String, dynamic>>();
        });
    // The server asks the client to apply a quick fix's edit via a request, not
    // through the command's own response. Acknowledging it is how a fix a
    // designer picks (applyCodeAction) actually takes effect on the server's side.
    _client.onRequest('workspace/applyEdit', (params) async {
      _appliedEdits.add(
        (params['edit'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
      return {'applied': true};
    });
  }

  /// The raw diagnostics last published for [path], for passing as code-action
  /// context. Empty before any diagnostics have arrived for it.
  List<Map<String, dynamic>> rawDiagnosticsFor(String path) =>
      _rawDiagnostics[_uri(path)] ?? const [];

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
      // workspace.applyEdit tells the server it may send us a workspace/applyEdit
      // request, which is how a quick fix's edit actually arrives (see
      // applyCodeAction). Without declaring it, the server refuses to run the
      // fix's command at all.
      'capabilities': <String, dynamic>{
        'workspace': {
          'applyEdit': true,
          'workspaceEdit': {'documentChanges': true},
        },
      },
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

  /// The analyzer's quick fixes at [line] and [character]. [diagnosticsJson] are the
  /// raw diagnostics covering that spot (from the last publishDiagnostics), which
  /// the server uses to match fixes to the right problem. Each item still needs
  /// [applyCodeAction] to get its edit: Dart's server returns a command to run, not
  /// the edit itself.
  Future<List<CodeActionItem>> codeActionsAt(
    String path,
    int line,
    int character, {
    List<Map<String, dynamic>> diagnosticsJson = const [],
  }) async {
    final result = await _client.request('textDocument/codeAction', {
      'textDocument': {'uri': _uri(path)},
      'range': {
        'start': {'line': line, 'character': character},
        'end': {'line': line, 'character': character},
      },
      'context': {'diagnostics': diagnosticsJson},
    });
    if (result is! List) return const [];
    return [
      for (final json in result.cast<Map<String, dynamic>>())
        ?_parseCodeAction(json),
    ];
  }

  /// Reads one entry of a code-action list. Dart's server returns a plain
  /// `Command` (title, command, arguments) rather than an edit directly; running
  /// it is [applyCodeAction]'s job. A `null` result means this entry had neither
  /// an edit nor a command, so there is nothing to offer for it.
  CodeActionItem? _parseCodeAction(Map<String, dynamic> json) {
    final title = json['title'] as String?;
    if (title == null) return null;
    if (json['edit'] != null) {
      return CodeActionItem(title, edit: parseWorkspaceEdit(json['edit']));
    }
    if (json['command'] is String) {
      return CodeActionItem(
        title,
        command: json['command'] as String,
        arguments: (json['arguments'] as List?)?.cast<Object?>(),
      );
    }
    final command = json['command'];
    if (command is Map && command['command'] is String) {
      return CodeActionItem(
        title,
        command: command['command'] as String,
        arguments: (command['arguments'] as List?)?.cast<Object?>(),
      );
    }
    return null;
  }

  /// Runs a quick fix and returns the edits it makes, grouped by file. A fix that
  /// already carried its edit returns it directly; one that only names a server
  /// command is executed, and the edit arrives back as a request from the server,
  /// which this acknowledges on the designer's behalf.
  Future<Map<String, List<TextEdit>>> applyCodeAction(
    CodeActionItem item,
  ) async {
    final direct = item.edit;
    if (direct != null) return direct;
    final command = item.command;
    if (command == null) return const {};
    final editFuture = _appliedEdits.stream.first.timeout(
      const Duration(seconds: 10),
      onTimeout: () => const {},
    );
    await _client.request('workspace/executeCommand', {
      'command': command,
      'arguments': item.arguments ?? const [],
    });
    final edit = await editFuture;
    return parseWorkspaceEdit(edit);
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
    await _appliedEdits.close();
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

/// One quick fix the analyzer offers: its label, and the edits it would make,
/// grouped by file.
class CodeActionItem {
  final String title;

  /// Set when the server gave the edit directly.
  final Map<String, List<TextEdit>>? edit;

  /// Set when applying this fix means running a server command first
  /// ([DartSession.applyCodeAction] does that and returns the resulting edit).
  final String? command;
  final List<Object?>? arguments;

  const CodeActionItem(this.title, {this.edit, this.command, this.arguments});
}
