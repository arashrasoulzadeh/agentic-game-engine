import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    // Reset to English so later suites don't inherit fa.
    LocalizationManager.instance.setLocale('en');
  });

  test('fa locale marks RTL and drives TextPainter direction', () async {
    await LocalizationFlutter.initialize(
      supportedLocales: const ['en', 'fa'],
      initialLocale: 'fa',
    );
    expect(LocalizationFlutter.isRTL, isTrue);
    expect(LocalizationFlutter.textDirection, ui.TextDirection.rtl);

    final painter = ui.ParagraphBuilder(
      ui.ParagraphStyle(textDirection: LocalizationFlutter.textDirection),
    )..addText('مبارز');
    final paragraph = painter.build()
      ..layout(const ui.ParagraphConstraints(width: 200));
    expect(paragraph.width, greaterThan(0));
  });

  test('en locale stays LTR', () async {
    await LocalizationFlutter.initialize(
      supportedLocales: const ['en', 'fa'],
      initialLocale: 'en',
    );
    expect(LocalizationFlutter.isRTL, isFalse);
    expect(LocalizationFlutter.textDirection, ui.TextDirection.ltr);
  });
}
