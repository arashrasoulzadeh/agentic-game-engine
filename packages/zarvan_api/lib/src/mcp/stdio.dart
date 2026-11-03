import 'dart:convert';

import 'rpc.dart';
import 'session.dart';

/// Serves [session] over newline-delimited JSON-RPC: one message per line in, one reply per line out.
///
/// Returns when [input] ends. Replies are written in request order, so a client that pipelines sees them in order.
Future<void> serveStdio(
  McpSession session,
  Stream<List<int>> input,
  void Function(String line) write,
) async {
  await for (final line
      in input
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final reply = await handleRpcText(line, session.dispatch);
    if (reply != null) write(reply);
  }
}
