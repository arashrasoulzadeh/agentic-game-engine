import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('a JSON object frame decodes and survives encode/decode', () {
    final message = {
      'type': 'order',
      'unit': 3,
      'to': [4, 5],
    };
    expect(decodeNetFrame(encodeNetFrame(message)), message);
  });

  test('anything else is null instead of throwing', () {
    expect(decodeNetFrame('not json'), isNull);
    expect(
      decodeNetFrame('[1,2,3]'),
      isNull,
      reason: 'an array is not a message',
    );
    expect(decodeNetFrame('42'), isNull);
    expect(decodeNetFrame(null), isNull);
    expect(decodeNetFrame([1, 2]), isNull, reason: 'a binary frame');
  });
}
