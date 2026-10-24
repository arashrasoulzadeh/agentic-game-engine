import 'dart:convert';

/// A JSON-RPC 2.0 failure to report to the caller (never an exception that escapes the transport).
class RpcException implements Exception {
  RpcException(this.code, this.message, [this.data]);

  /// Standard JSON-RPC code (-32700 parse, -32600 invalid request, -32601 no method, -32602 bad params,
  /// -32603 internal) or one of the engine's -320xx codes.
  final int code;
  final String message;
  final Object? data;

  @override
  String toString() => 'RpcException($code): $message';
}

/// The JSON-RPC error response for request [id] (null when the id could not be read).
Map<String, Object?> rpcError(
  Object? id,
  int code,
  String message, [
  Object? data,
]) => {
  'jsonrpc': '2.0',
  'id': id,
  'error': {'code': code, 'message': message, if (data != null) 'data': data},
};

/// Answers one parsed JSON-RPC message, or a batch of them, with [dispatch] doing the work per method.
///
/// Notifications (no `id`) never get a reply, so a batch of only notifications returns null. Shared by the stdio
/// and HTTP transports so both behave identically.
Future<Object?> handleRpc(
  Object? message,
  Future<Object?> Function(String method, Map<String, Object?> params) dispatch,
) async {
  if (message is List) {
    if (message.isEmpty) return rpcError(null, -32600, 'Empty batch');
    final replies = <Object?>[];
    for (final m in message) {
      final r = await handleRpc(m, dispatch);
      if (r != null) replies.add(r);
    }
    return replies.isEmpty ? null : replies;
  }
  if (message is! Map || message['method'] is! String) {
    return rpcError(
      message is Map ? message['id'] : null,
      -32600,
      'Invalid Request',
    );
  }
  final id = message['id'];
  final rawParams = message['params'];
  if (rawParams != null && rawParams is! Map) {
    return id == null ? null : rpcError(id, -32602, 'params must be an object');
  }
  try {
    final result = await dispatch(
      message['method'] as String,
      (rawParams as Map?)?.cast<String, Object?>() ?? {},
    );
    return id == null ? null : {'jsonrpc': '2.0', 'id': id, 'result': result};
  } on RpcException catch (e) {
    return id == null ? null : rpcError(id, e.code, e.message, e.data);
  } catch (_) {
    return id == null ? null : rpcError(id, -32603, 'Internal error');
  }
}

/// Parses one line of text as JSON-RPC and answers it; a parse failure is a `-32700` reply.
Future<String?> handleRpcText(
  String text,
  Future<Object?> Function(String method, Map<String, Object?> params) dispatch,
) async {
  Object? parsed;
  try {
    parsed = jsonDecode(text);
  } on FormatException {
    return jsonEncode(rpcError(null, -32700, 'Parse error'));
  }
  final reply = await handleRpc(parsed, dispatch);
  return reply == null ? null : jsonEncode(reply);
}
