import 'package:engine_core/engine_core_ops.dart';

import '../version.dart';

/// The OpenAPI 3.1 document for the REST surface, generated from the registry so it cannot drift from the operations.
Map<String, Object?> openApiFor(Iterable<Operation> operations) => {
  'openapi': '3.1.0',
  'info': {
    'title': 'engine_api',
    'version': engineApiVersion,
    'description':
        'One POST per operation; the body is the parameters object and the response is the result envelope.',
  },
  'components': {
    'securitySchemes': {
      'bearer': {'type': 'http', 'scheme': 'bearer'},
    },
  },
  'security': [
    {'bearer': <String>[]},
  ],
  'paths': {
    for (final op in operations)
      '/v1/${op.group}/${op.verb}': {
        'post': {
          'operationId': op.name,
          'summary': op.summary,
          'description': op.description,
          'tags': [op.group],
          'requestBody': {
            'content': {
              'application/json': {'schema': inputSchemaFor(op)},
            },
          },
          'responses': {
            '200': {'description': 'The result envelope (ok:true).'},
            for (final c in {
              ErrorCode.invalidParams,
              ErrorCode.notFound,
              ErrorCode.conflict,
              ...op.errors.keys,
            })
              '${c.http}': {'description': c.code},
          },
        },
      },
  },
};
