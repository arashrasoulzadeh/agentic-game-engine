import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A client for the Dart language server (`dart language-server`), the same server
/// other editors use. It gives real completions, including members and engine
/// classes, from the analyzer.
///
/// Messages use the Language Server Protocol's framing: a `Content-Length` header,
/// a blank line, then a JSON body. Requests get their response by `id`.
class LspClient {
  final Stream<List<int>> _input;
  final void Function(List<int>) _output;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _requestHandlers =
      <String, Future<Map<String, dynamic>> Function(Map<String, dynamic>)>{};
  final _notifications = StreamController<Map<String, dynamic>>.broadcast();
  final _buffer = BytesBuilder(copy: false);
  int _nextId = 1;

  LspClient({
    required Stream<List<int>> input,
    required void Function(List<int>) output,
  }) : _input = input,
       _output = output {
    _input.listen(_onBytes);
  }

  /// Starts the language server for [projectRoot] and wraps its pipes.
  static Future<LspClient> start({
    String dart = 'dart',
    required String projectRoot,
  }) async {
    final process = await Process.start(dart, [
      'language-server',
      '--protocol=lsp',
    ], workingDirectory: projectRoot);
    return LspClient(input: process.stdout, output: process.stdin.add);
  }

  /// Sends a request and completes with its `result`. An error response completes
  /// with a [StateError] carrying the server's message.
  Future<dynamic> request(String method, Map<String, dynamic> params) {
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return completer.future.then((message) {
      final error = message['error'];
      if (error != null) {
        throw StateError('${(error as Map)['message']}');
      }
      return message['result'];
    });
  }

  /// Messages the server sends without being asked, such as diagnostics.
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  /// Sends a notification, which expects no response.
  void notify(String method, Map<String, dynamic> params) {
    _send({'jsonrpc': '2.0', 'method': method, 'params': params});
  }

  /// Handles a request the server sends to the client, such as
  /// `workspace/applyEdit` (the server asking the client to write an edit). The
  /// handler's return value is sent back as the response's `result`.
  void onRequest(
    String method,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> params) handler,
  ) {
    _requestHandlers[method] = handler;
  }

  void _send(Map<String, dynamic> message) {
    final body = utf8.encode(jsonEncode(message));
    _output([
      ...ascii.encode('Content-Length: ${body.length}\r\n\r\n'),
      ...body,
    ]);
  }

  void _onBytes(List<int> chunk) {
    _buffer.add(chunk);
    while (true) {
      final bytes = _buffer.toBytes();
      final headerEnd = _indexOfHeaderEnd(bytes);
      if (headerEnd < 0) return;
      final header = ascii.decode(bytes.sublist(0, headerEnd));
      final match = RegExp(
        r'Content-Length: (\d+)',
        caseSensitive: false,
      ).firstMatch(header);
      if (match == null) return;
      final length = int.parse(match.group(1)!);
      final bodyStart = headerEnd + 4;
      if (bytes.length < bodyStart + length) return;
      final body = bytes.sublist(bodyStart, bodyStart + length);
      _buffer.clear();
      _buffer.add(bytes.sublist(bodyStart + length));
      _dispatch(jsonDecode(utf8.decode(body)) as Map<String, dynamic>);
    }
  }

  void _dispatch(Map<String, dynamic> message) {
    final id = message['id'];
    final method = message['method'];
    if (id is int && _pending.containsKey(id)) {
      _pending.remove(id)!.complete(message);
    } else if (id != null && method is String) {
      // A request from the server to the client, not a response to one of ours.
      _handleServerRequest(
        id,
        method,
        (message['params'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
    } else if (method is String && !_notifications.isClosed) {
      _notifications.add(message);
    }
  }

  Future<void> _handleServerRequest(
    Object id,
    String method,
    Map<String, dynamic> params,
  ) async {
    final handler = _requestHandlers[method];
    if (handler == null) {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32601, 'message': 'Method not found: $method'},
      });
      return;
    }
    try {
      final result = await handler(params);
      _send({'jsonrpc': '2.0', 'id': id, 'result': result});
    } on Object catch (e) {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32603, 'message': '$e'},
      });
    }
  }

  static int _indexOfHeaderEnd(Uint8List bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  /// Closes the server's pipes. The server exits when its input ends.
  Future<void> dispose() async {
    _pending.clear();
    await _notifications.close();
  }
}
