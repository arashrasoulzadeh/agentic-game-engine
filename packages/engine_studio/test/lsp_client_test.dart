import 'dart:async';
import 'dart:convert';

import 'package:engine_studio/src/lsp/lsp_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Frames a message the way the server does, for feeding the client a response.
List<int> _frame(Map<String, dynamic> message) {
  final body = utf8.encode(jsonEncode(message));
  return [...utf8.encode('Content-Length: ${body.length}\r\n\r\n'), ...body];
}

void main() {
  test(
    'a request is framed with Content-Length and completes from its response',
    () async {
      final sent = <int>[];
      final incoming = StreamController<List<int>>();
      final client = LspClient(input: incoming.stream, output: sent.addAll);

      final result = client.request('textDocument/completion', {'line': 1});
      final text = utf8.decode(sent);
      expect(text, startsWith('Content-Length: '));
      final body = text.substring(text.indexOf('\r\n\r\n') + 4);
      final request = jsonDecode(body) as Map<String, dynamic>;
      expect(request['method'], 'textDocument/completion');

      incoming.add(
        _frame({
          'jsonrpc': '2.0',
          'id': request['id'],
          'result': ['ok'],
        }),
      );
      expect(await result, ['ok']);
      await incoming.close();
    },
  );

  test(
    'a response split across chunks is reassembled before it is read',
    () async {
      final sent = <int>[];
      final incoming = StreamController<List<int>>();
      final client = LspClient(input: incoming.stream, output: sent.addAll);
      final result = client.request('m', {});
      final id = jsonDecode(utf8.decode(sent).split('\r\n\r\n').last)['id'];

      final bytes = _frame({'jsonrpc': '2.0', 'id': id, 'result': 42});
      incoming.add(bytes.sublist(0, 10));
      incoming.add(bytes.sublist(10));
      expect(await result, 42);
      await incoming.close();
    },
  );

  test('an error response becomes an error for the caller', () async {
    final sent = <int>[];
    final incoming = StreamController<List<int>>();
    final client = LspClient(input: incoming.stream, output: sent.addAll);
    final result = client.request('m', {});
    final id = jsonDecode(utf8.decode(sent).split('\r\n\r\n').last)['id'];
    incoming.add(
      _frame({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'message': 'boom'},
      }),
    );
    await expectLater(result, throwsA(isA<StateError>()));
    await incoming.close();
  });
}
