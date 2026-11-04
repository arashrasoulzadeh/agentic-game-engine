import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults are the identity; any strength is not', () {
    expect(const ShaderPostFx().isIdentity, isTrue);
    expect(const ShaderPostFx(bloom: 0.1).isIdentity, isFalse);
    expect(const ShaderPostFx.crt().isIdentity, isFalse);
    expect(const ShaderPostFx(pixelSize: 4).isIdentity, isFalse);
  });

  test('uniforms follow the shader layout (12 floats after uSize)', () {
    final u = const ShaderPostFx(
      bloom: 1,
      bloomThreshold: 2,
      bloomRadius: 3,
      chromaticAberration: 4,
      pixelSize: 5,
      scanlines: 6,
      curvature: 7,
      vignette: 8,
      grain: 10,
      phosphorMask: 11,
      scanlineSpacing: 12,
    ).toUniforms(9);
    expect(u, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
  });

  test('the shader compiles and takes exactly those uniforms', () async {
    final program = await ui.FragmentProgram.fromAsset(
      'shaders/post_fx.frag',
    );
    final shader = program.fragmentShader();
    // uSize (2) + 12 floats, then one sampler: setting float 13 must fail.
    for (var i = 0; i < 14; i++) {
      shader.setFloat(i, 0);
    }
    expect(() => shader.setFloat(14, 0), throwsA(anything));
    shader.dispose();
  });

  testWidgets('identity shows the child; strengths keep it mounted', (t) async {
    const child = SizedBox(key: Key('c'), width: 50, height: 50);
    await t.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ShaderPostProcessed(fx: ShaderPostFx(), child: child),
      ),
    );
    expect(find.byKey(const Key('c')), findsOneWidget);
    await t.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ShaderPostProcessed(fx: ShaderPostFx.crt(), child: child),
      ),
    );
    await t.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('c')), findsOneWidget);
  });
}
