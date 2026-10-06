import 'package:engine_studio/src/code/dart_highlighter.dart';
import 'package:engine_studio/src/code/marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a marked error is drawn with a wavy underline and the rest is not',
    (tester) async {
      final controller = DartHighlightController(text: 'var x = bad;')
        ..marks = const [TextMark(8, 11, isError: true)];
      late TextSpan span;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );
              return const SizedBox();
            },
          ),
        ),
      );

      final runs = span.children!.cast<TextSpan>();
      final bad = runs.firstWhere((r) => r.text == 'bad');
      expect(bad.style?.decoration, TextDecoration.underline);
      expect(bad.style?.decorationStyle, TextDecorationStyle.wavy);
      expect(bad.style?.decorationColor, const Color(0xFFF14C4C));

      final plain = runs.where((r) => r.text == 'var' || r.text == 'x');
      for (final run in plain) {
        expect(run.style?.decoration, isNull);
      }
    },
  );
}
