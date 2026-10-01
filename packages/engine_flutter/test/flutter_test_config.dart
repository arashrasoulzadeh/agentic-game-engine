import 'dart:async';
import 'dart:io';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // A package tested directly bundles its shaders at the root; consuming
  // apps bundle them under packages/engine_flutter. Mirror that app asset
  // key for every shader this package declares (pubspec.yaml's `shaders:`
  // list) so the shader-dependent tests exercise the compiled shader
  // through the production loader instead of always hitting the
  // null-shader fallback path.
  const shaderNames = [
    'light_shadow.frag',
    'ambient_lighting.frag',
    'normal_mapping.frag',
    'normal_mapping_combined.frag',
    'colorblind.frag',
  ];
  for (final name in shaderNames) {
    final compiled = File('build/unit_test_assets/shaders/$name');
    final packaged = File(
      'build/unit_test_assets/packages/engine_flutter/shaders/$name',
    );
    // Only light_shadow.frag's own test exercises the "asset missing"
    // fallback path, via ENGINE_TEST_SHADER_ASSET=missing.
    if (name == 'light_shadow.frag' &&
        Platform.environment['ENGINE_TEST_SHADER_ASSET'] == 'missing') {
      if (packaged.existsSync()) packaged.deleteSync();
      continue;
    }
    if (compiled.existsSync()) {
      packaged.parent.createSync(recursive: true);
      compiled.copySync('${packaged.path}.$pid.tmp').renameSync(packaged.path);
    }
  }
  await testMain();
}
