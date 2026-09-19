import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sprite round-trips through toJson/fromJson with defaults', () {
    final sprite = Sprite('atlas', 'idle');
    final decoded = Sprite.fromJson(sprite.toJson());

    expect(decoded.atlasId, 'atlas');
    expect(decoded.region, 'idle');
    expect(decoded.rotation, 0);
    expect(decoded.scaleX, 1);
    expect(decoded.scaleY, 1);
    expect(decoded.screenSpace, isFalse);
    expect(decoded.offsetX, 0);
    expect(decoded.offsetY, 0);
  });

  test('Sprite.fromJson honors explicit offsetX/offsetY', () {
    final decoded = Sprite.fromJson(Sprite('atlas', 'idle', offsetX: -4, offsetY: 12).toJson());
    expect(decoded.offsetX, -4);
    expect(decoded.offsetY, 12);
  });

  test('Sprite.fromJson honors explicit screenSpace', () {
    final decoded = Sprite.fromJson(Sprite('atlas', 'idle', screenSpace: true).toJson());
    expect(decoded.screenSpace, isTrue);
  });

  test('Sprite.fromJson honors explicit rotation/scale', () {
    final sprite = Sprite('atlas', 'idle', rotation: 1.5, scaleX: 2, scaleY: 3);
    final decoded = Sprite.fromJson(sprite.toJson());

    expect(decoded.rotation, 1.5);
    expect(decoded.scaleX, 2);
    expect(decoded.scaleY, 3);
  });
}
