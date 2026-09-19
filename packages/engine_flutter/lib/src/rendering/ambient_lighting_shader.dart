import 'dart:ui' as ui;

/// Loads and caches the compiled `ambient_lighting.frag` shader used by
/// `EngineView` for the single-pass ambient lighting approach — computes
/// the combined darkness mask for all lights in one fragment shader
/// invocation, replacing the saveLayer + dark rect + N light hole draws
/// (BlendMode.dstOut) with one full-screen quad draw.
///
/// `FragmentProgram.fromAsset` is async (a real shader compile), while
/// `CustomPainter.paint` is synchronous — this loads it once, in the
/// background, the first time [shader] is called, and every call
/// before that completes returns `null` (the single-pass lighting is
/// silently skipped that frame, falling back to the legacy multi-pass
/// approach). Loading is near-instant in practice (shader compilation,
/// not asset decode), so this is a one-or-two-frame gap at worst.
class AmbientLightingShader {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  /// The correct `rootBundle` key for a shader declared in *this*
  /// package's own `pubspec.yaml` (`flutter: shaders:`), read from a
  /// consuming app's isolate — a package's own declared assets/shaders
  /// live under `packages/<package name>/<path>` in the merged asset
  /// bundle, not the bare path the package's `pubspec.yaml` lists.
  static const String _defaultAssetKey =
      'packages/engine_flutter/shaders/ambient_lighting.frag';

  /// Override the asset key for testing (e.g., to trigger the error path).
  /// Only for testing — production code should never call this.
  static String _assetKey = _defaultAssetKey;

  /// A fresh `FragmentShader` instance ready to have its uniforms set,
  /// or `null` if the program hasn't finished compiling yet (kicks off
  /// loading it if this is the first call), or if loading it failed —
  /// an environment that genuinely can't build/bundle the shader asset
  /// (a stripped-down CI runner, a sandboxed dev environment with no
  /// package-resolution access) degrades to "the single-pass lighting
  /// is permanently skipped," falling back to the legacy multi-pass
  /// approach, rather than an unhandled async exception escaping into
  /// `CustomPainter.paint`. A `FragmentShader` carries its own uniform
  /// state and can't be reused concurrently, so callers get a new
  /// instance per call.
  static ui.FragmentShader? shader() {
    final program = _program;
    if (program != null) return program.fragmentShader();
    _loading ??= ui.FragmentProgram.fromAsset(_assetKey).then(
      (p) => _program = p,
      onError: (Object _, StackTrace __) {
        // Swallowed deliberately — see this method's own doc comment.
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