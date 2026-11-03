import 'dart:ui' as ui;

import 'package:zarvan_core/zarvan_core.dart';

import 'ambient_lighting_shader.dart';
import 'gpu_light_shader.dart';
import 'light2d.dart';
import 'normal_mapping_combined_shader.dart';
import 'normal_mapping_shader.dart';
import 'sprite.dart';

/// Warms up the GPU-side systems a [World] will actually use, during loading.
///
/// Fragment programs compile lazily on first paint, so without this the first
/// frame that needs lighting or normal mapping draws without it and the
/// pipeline compile lands in a visible frame. Only what the world needs is
/// touched: no lights, no lighting shaders. Never throws: a shader that cannot
/// load degrades exactly as it already does at paint time.
class EngineWarmup {
  /// Shaders [world] needs, by name (`ambient`, `gpuShadow`, `normalMap`).
  static Set<String> neededShaders(World world) {
    final needs = <String>{};
    final lights = world.componentsOf<Light2D>();
    for (var i = 0; i < lights.length; i++) {
      final light = lights.denseAt(i);
      needs.add('ambient');
      if (light.useGpuShadows && light.castsShadows) needs.add('gpuShadow');
    }
    final sprites = world.componentsOf<Sprite>();
    for (var i = 0; i < sprites.length; i++) {
      if (sprites.denseAt(i).normalAtlasId != null) {
        needs.add('normalMap');
        break;
      }
    }
    return needs;
  }

  /// Compiles [neededShaders] and draws each once into a 1x1 offscreen image
  /// so the GPU pipeline is built before the first visible frame. Reports
  /// `(fraction, label)` as it goes.
  static Future<void> run(
    World world, {
    void Function(double fraction, String label)? report,
  }) async {
    final needs = neededShaders(world);
    final steps =
        <(String, Future<void> Function(), ui.FragmentShader? Function())>[
          if (needs.contains('ambient'))
            (
              'lighting',
              AmbientLightingShader.warmUp,
              AmbientLightingShader.shader,
            ),
          if (needs.contains('gpuShadow'))
            ('shadows', GpuLightShader.warmUp, GpuLightShader.shader),
          if (needs.contains('normalMap')) ...[
            (
              'normal maps',
              NormalMappingShader.warmUp,
              NormalMappingShader.shader,
            ),
            (
              'normal maps',
              NormalMappingCombinedShader.warmUp,
              NormalMappingCombinedShader.shader,
            ),
          ],
        ];
    for (var i = 0; i < steps.length; i++) {
      final (label, load, make) = steps[i];
      report?.call(i / steps.length, 'Warming up $label');
      try {
        await load();
        final shader = make();
        if (shader != null) _drawOnce(shader);
      } on Object {
        // Same fallback as paint time: the feature is skipped, not fatal.
      }
    }
    report?.call(1, 'Warming up');
  }

  static void _drawOnce(ui.FragmentShader shader) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint()..shader = shader);
    final picture = recorder.endRecording();
    picture.toImageSync(1, 1).dispose();
    picture.dispose();
  }
}
