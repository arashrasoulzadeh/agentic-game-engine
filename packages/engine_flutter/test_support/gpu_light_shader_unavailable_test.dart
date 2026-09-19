import 'dart:io';

import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/flutter_test_config.dart' as configuration;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missing shader assets leave the optional GPU pass unavailable without throwing', () async {
    expect(Platform.environment['ENGINE_TEST_SHADER_ASSET'], 'missing');
    await configuration.testExecutable(() async {
      expect(GpuLightShader.shader(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(GpuLightShader.shader(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(GpuLightShader.shader(), isNull);
    });
  });
}
