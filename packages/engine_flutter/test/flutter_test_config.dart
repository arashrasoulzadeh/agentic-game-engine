import 'dart:async';
import 'dart:io';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // A package tested directly bundles its shader at the root; consuming apps
  // bundle it under packages/engine_flutter. Mirror that app asset key so the
  // GPU tests exercise the compiled shader through the production loader.
  final compiled = File('build/unit_test_assets/shaders/light_shadow.frag');
  final packaged = File(
    'build/unit_test_assets/packages/engine_flutter/shaders/light_shadow.frag',
  );
  if (Platform.environment['ENGINE_TEST_SHADER_ASSET'] == 'missing') {
    if (packaged.existsSync()) packaged.deleteSync();
  } else if (compiled.existsSync()) {
    packaged.parent.createSync(recursive: true);
    compiled.copySync('${packaged.path}.$pid.tmp').renameSync(packaged.path);
  }
  await testMain();
}
