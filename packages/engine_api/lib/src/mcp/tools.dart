import 'dart:convert';

import 'package:engine_core/engine_core_ops.dart';

/// The text an agent reads to decide how to call [op]: what it does, its kind, error codes and examples.
///
/// This is the "enough detail for the agent" requirement: everything the agent needs is in the tool description,
/// so it does not have to guess or fetch another document.
String renderToolDescription(Operation op) {
  final b = StringBuffer(op.summary);
  if (op.description.isNotEmpty) b.write('\n\n${op.description}');
  b.write('\n\nKind: ');
  b.write(switch (op.kind) {
    OperationKind.read => 'read (changes nothing).',
    OperationKind.write =>
      'write (applies by default; pass apply:false to preview, undo with undo.undo).',
    OperationKind.destructive =>
      'destructive (call once to get a preview and a confirmation token, then again with that token).',
  });
  if (op.scope == OperationScope.project) {
    b.write(' Needs an open project (project.open).');
  }
  if (op.errors.isNotEmpty) {
    b.write('\n\nErrors:');
    for (final e in op.errors.entries) {
      b.write('\n- ${e.key.code}: ${e.value}');
    }
  }
  for (final e in op.examples) {
    b.write('\n\nExample - ${e.title}:\n${jsonEncode(e.args)}');
  }
  return b.toString();
}

/// The MCP tool definition for [op]; [name] is the (possibly style-converted) tool name.
Map<String, Object?> toolFor(Operation op, {String? name}) => {
  'name': name ?? op.name,
  'title': op.summary,
  'description': renderToolDescription(op),
  'inputSchema': inputSchemaFor(op),
  'annotations': {
    'readOnlyHint': op.kind == OperationKind.read,
    'destructiveHint': op.kind == OperationKind.destructive,
    'idempotentHint': op.idempotent,
    'openWorldHint': false,
  },
};

/// Wraps an operation result as an MCP `tools/call` result (`isError` mirrors `ok:false`).
///
/// When the successful data carries a `pngBase64` field (e.g. `level.lint` with
/// `includeRender`), also emits an `image` content part so MCP clients can show
/// the preview without digging into the JSON envelope.
Map<String, Object?> toolResult(OpResult result) {
  final envelope = result.toJson();
  final content = <Map<String, Object?>>[
    {
      'type': 'text',
      'text': const JsonEncoder.withIndent('  ').convert(envelope),
    },
  ];
  final data = envelope['data'];
  if (envelope['ok'] == true && data is Map && data['pngBase64'] is String) {
    content.add({
      'type': 'image',
      'data': data['pngBase64'],
      'mimeType': 'image/png',
    });
  }
  return {
    'content': content,
    'structuredContent': envelope,
    'isError': envelope['ok'] != true,
  };
}
