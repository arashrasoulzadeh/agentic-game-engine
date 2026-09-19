import 'dart:ui' as ui;

/// Loads and caches the compiled `light_shadow.frag` shader used by
/// `Light2D.useGpuShadows` — a real GPU-based point light with
/// per-pixel shadow occlusion (ray-vs-line-segment intersection tests
/// run in parallel across every pixel), replacing the CPU
/// `raycastTileMap` sweep the default shadow-casting path uses. See
/// the shader source's own doc comment for the algorithm.
///
/// `FragmentProgram.fromAsset` is async (a real shader compile), while
/// `CustomPainter.paint` is synchronous — this loads it once, in the
/// background, the first time [shader] is called, and every call
/// before that completes returns `null` (the GPU-shadow pass for a
/// light is silently skipped that frame, same "renders as if the
/// feature doesn't exist yet" fallback this engine already uses
/// elsewhere for a not-yet-loaded atlas). Loading is near-instant in
/// practice (shader compilation, not asset decode), so this is a
/// one-or-two-frame gap at worst, not a visible pop.
class GpuLightShader {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  /// The correct `rootBundle` key for a shader declared in *this*
  /// package's own `pubspec.yaml` (`flutter: shaders:`), read from a
  /// consuming app's isolate — a package's own declared assets/shaders
  /// live under `packages/<package name>/<path>` in the merged asset
  /// bundle, not the bare path the package's `pubspec.yaml` lists.
  static const String _defaultAssetKey = 'packages/engine_flutter/shaders/light_shadow.frag';

  /// Override the asset key for testing (e.g., to trigger the error path).
  /// Only for testing — production code should never call this.
  static String _assetKey = _defaultAssetKey;

  /// A fresh `FragmentShader` instance ready to have its uniforms set,
  /// or `null` if the program hasn't finished compiling yet (kicks off
  /// loading it if this is the first call), or if loading it failed —
  /// an environment that genuinely can't build/bundle the shader asset
  /// (a stripped-down CI runner, a sandboxed dev environment with no
  /// package-resolution access) degrades to "the GPU-shadow pass is
  /// permanently skipped for every light," the same fallback as not
  /// having loaded yet, rather than an unhandled async exception
  /// escaping into `CustomPainter.paint`. A `FragmentShader` carries
  /// its own uniform state and can't be reused concurrently across
  /// multiple lights in the same frame, so callers get a new instance
  /// per call rather than one shared instance.
  static ui.FragmentShader? shader() {
    final program = _program;
    if (program != null) return program.fragmentShader();
    _loading ??= ui.FragmentProgram.fromAsset(_assetKey).then(
      (p) => _program = p,
      onError: (Object _, StackTrace __) {
        // Swallowed deliberately -- see this method's own doc comment.
      },
    );
    return null;
  }

  /// Resets the cached shader program and loading future.
  /// Only for testing — allows simulating a fresh load or an error.
  static void resetForTesting() {
    _program = null;
    _loading = null;
    _assetKey = _defaultAssetKey;
  }

  /// Overrides the asset key for testing (e.g., to trigger the error path).
  /// Only for testing — production code should never call this.
  static void setAssetKeyForTesting(String key) {
    _assetKey = key;
  }
}