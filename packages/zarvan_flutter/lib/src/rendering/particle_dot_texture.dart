import 'dart:ui' as ui;

/// A tiny, solid-white circle rasterized once and cached, used by
/// `EngineView._collectParticleItems` to batch many particles into a
/// single `Canvas.drawAtlas` call instead of one `drawCircle` call per
/// particle (a real, measured win for sprite rendering already —
/// `_collectSpriteItems`'s own doc comment — and the same shape of
/// problem: many small same-source draws per frame). Tinted per-particle
/// via `drawAtlas`'s own `colors` + `BlendMode.modulate` (white * color
/// == color, alpha included), so this texture carries no color/alpha of
/// its own beyond "fully opaque white" — the actual per-particle look
/// comes entirely from that per-instance tint, not from this image.
class ParticleDotTexture {
  static ui.Image? _image;
  static Future<void>? _loading;

  /// Native pixel size of the generated square texture — also the
  /// unscaled diameter of the circle drawn into it, so a `drawAtlas`
  /// `RSTransform` scale factor of exactly `radius / (size / 2)`
  /// reproduces a circle of that radius with no further math needed at
  /// the call site.
  static const int size = 8;

  /// The cached texture, or `null` if it hasn't finished generating yet
  /// (kicks off generation on first call, fire-and-forget) — callers
  /// fall back to the original per-particle `drawCircle` path until
  /// this resolves, the same "degrade gracefully, retry next frame"
  /// pattern `GpuLightShader.shader()` uses for its own async-loaded
  /// resource. Unlike that shader, this is pure runtime rasterization
  /// (`dart:ui` only, no asset bundle/`pub get` involved), so it
  /// resolves within the first frame or two in any environment that can
  /// run Flutter at all.
  static ui.Image? image() {
    final img = _image;
    if (img != null) return img;
    _loading ??= _generate().then((i) => _image = i);
    return null;
  }

  static Future<ui.Image> _generate() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawCircle(
      const ui.Offset(size / 2, size / 2),
      size / 2,
      ui.Paint()
        ..color = const ui.Color(0xFFFFFFFF)
        ..isAntiAlias = true,
    );
    final picture = recorder.endRecording();
    return picture.toImage(size, size);
  }
}
