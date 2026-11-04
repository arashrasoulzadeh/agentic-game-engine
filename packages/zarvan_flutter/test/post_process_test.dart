import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart';

void main() {
  test('a neutral grade is the identity matrix', () {
    final m = const ColorGrade().toMatrix();
    expect(m, [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]);
  });

  test('zero saturation makes all colour rows equal (greyscale)', () {
    final m = const ColorGrade(saturation: 0).toMatrix();
    expect(m.sublist(0, 3), m.sublist(5, 8));
    expect(m.sublist(0, 3), m.sublist(10, 13));
  });

  test('brightness scales and contrast pivots on mid-grey', () {
    final b = const ColorGrade(brightness: 0.5).toMatrix();
    expect(b[0], closeTo(0.5, 1e-9));
    final c = const ColorGrade(contrast: 2).toMatrix();
    expect(c[0], closeTo(2, 1e-9));
    expect(c[4], closeTo(-127.5, 1e-9));
  });

  test('composing grades multiplies their effect', () {
    final m = composeGrades(const [
      ColorGrade(brightness: 0.5),
      ColorGrade(brightness: 0.5),
    ]);
    expect(m[0], closeTo(0.25, 1e-9));
    expect(composeGrades(const []), const ColorGrade().toMatrix());
  });

  testWidgets('grades add one filter; overlays add a painter on top', (
    t,
  ) async {
    await t.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 100,
          height: 100,
          child: PostProcessed(
            effects: [
              ColorGrade(saturation: 0),
              ColorGrade(brightness: 0.8),
              Vignette(),
              Scanlines(),
            ],
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(find.byType(IgnorePointer), findsWidgets);
  });

  testWidgets('with no effects the child is returned untouched', (t) async {
    await t.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: PostProcessed(
          effects: [],
          child: SizedBox(key: Key('c')),
        ),
      ),
    );
    expect(find.byType(ColorFiltered), findsNothing);
    expect(find.byKey(const Key('c')), findsOneWidget);
  });
}
