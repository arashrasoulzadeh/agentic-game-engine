import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Text round-trips through toJson/fromJson with defaults', () {
    final text = Text('Score: 0');
    final decoded = Text.fromJson(text.toJson());

    expect(decoded.text, 'Score: 0');
    expect(decoded.fontSize, 16);
    expect(decoded.colorArgb, 0xFFFFFFFF);
    expect(decoded.align, TextAlignment.center);
    expect(decoded.screenSpace, isFalse);
    expect(decoded.zIndex, 0);
  });

  test('Text.fromJson honors explicit fields', () {
    final text = Text(
      '+10',
      fontSize: 24,
      colorArgb: 0xFFFF0000,
      align: TextAlignment.left,
      screenSpace: true,
      zIndex: 5,
    );
    final decoded = Text.fromJson(text.toJson());

    expect(decoded.text, '+10');
    expect(decoded.fontSize, 24);
    expect(decoded.colorArgb, 0xFFFF0000);
    expect(decoded.align, TextAlignment.left);
    expect(decoded.screenSpace, isTrue);
    expect(decoded.zIndex, 5);
  });

  test('Text.fromJson defaults align to center for an unrecognized value', () {
    final decoded = Text.fromJson({'text': 'x', 'align': 'not-a-real-alignment'});
    expect(decoded.align, TextAlignment.center);
  });

  test('maxWidth defaults to null (unbounded, single-line) and round-trips when set', () {
    expect(Text('x').maxWidth, isNull);
    expect(Text.fromJson(Text('x').toJson()).maxWidth, isNull);
    expect(Text.fromJson({'text': 'x'}).maxWidth, isNull);

    final decoded = Text.fromJson(Text('a long line', maxWidth: 120).toJson());
    expect(decoded.maxWidth, 120);
  });
}
