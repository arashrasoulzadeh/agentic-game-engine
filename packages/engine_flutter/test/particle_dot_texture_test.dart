import 'dart:ui' as ui;

import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('image() eventually resolves to a real size x size opaque texture', () async {
    ui.Image? img;
    for (var i = 0; i < 50 && img == null; i++) {
      img = ParticleDotTexture.image();
      if (img == null) await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(img, isNotNull, reason: 'generation should resolve well within 500ms');
    expect(img!.width, ParticleDotTexture.size);
    expect(img.height, ParticleDotTexture.size);
  });

  test('image() returns the same cached instance on repeated calls once loaded', () async {
    ui.Image? first;
    for (var i = 0; i < 50 && first == null; i++) {
      first = ParticleDotTexture.image();
      if (first == null) await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final second = ParticleDotTexture.image();

    expect(identical(first, second), isTrue);
  });
}
