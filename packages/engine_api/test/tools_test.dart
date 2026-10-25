import 'package:engine_api/src/mcp/tools.dart';
import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

void main() {
  test('toolResult includes an image part when data has pngBase64', () {
    final result = OpResult.success({
      'ok': true,
      'pngBase64': 'aW1hZ2U=',
      'render': {'cols': 2, 'rows': 2},
    });
    final out = toolResult(result);
    final content = (out['content'] as List).cast<Map>();
    expect(content.first['type'], 'text');
    expect(content, hasLength(2));
    expect(content[1]['type'], 'image');
    expect(content[1]['data'], 'aW1hZ2U=');
    expect(content[1]['mimeType'], 'image/png');
    expect(out['isError'], false);
  });

  test('toolResult stays text-only without pngBase64', () {
    final out = toolResult(OpResult.success({'ok': true}));
    expect((out['content'] as List), hasLength(1));
  });
}
