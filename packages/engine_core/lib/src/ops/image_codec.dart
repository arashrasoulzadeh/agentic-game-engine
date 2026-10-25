import 'dart:typed_data';

/// A decoded raster the packer and render ops share. Opaque to core — only the injected
/// [ImageCodec] creates, resizes and composites them (so `engine_core` never depends on
/// `package:image`).
abstract class EngineImage {
  int get width;
  int get height;
}

/// An opaque RGB(A) colour for [ImageCodec] drawing helpers.
class EngineColor {
  const EngineColor(this.r, this.g, this.b, [this.a = 255]);

  final int r, g, b, a;
}

/// Decode / resize / encode / draw for operations that need pixels (`asset.pack`,
/// `level.lint` render). `engine_cli` and `engine_api` each supply a thin wrapper over
/// `package:image`; without one those ops return [ErrorCode.unsupported].
abstract class ImageCodec {
  /// Decodes [bytes], or null when the bytes are not a recognised image.
  EngineImage? decode(Uint8List bytes);

  /// A fresh image at [scale] of [source]'s size (at least 1×1).
  EngineImage resize(EngineImage source, double scale);

  /// An empty (transparent) RGBA canvas.
  EngineImage create(int width, int height);

  /// Fills the whole image with [color].
  void fill(EngineImage image, EngineColor color);

  /// Fills the inclusive rectangle with [color].
  void fillRect(
    EngineImage image, {
    required int x1,
    required int y1,
    required int x2,
    required int y2,
    required EngineColor color,
  });

  /// Fills a disc centred at ([x], [y]).
  void fillCircle(
    EngineImage image, {
    required int x,
    required int y,
    required int radius,
    required EngineColor color,
  });

  /// Draws [text] with a small bitmap font (labels on lint previews).
  void drawString(
    EngineImage image,
    String text, {
    required int x,
    required int y,
    required EngineColor color,
  });

  /// Copies [src] onto [dest] at ([dstX], [dstY]) without blending.
  void composite(
    EngineImage dest,
    EngineImage src, {
    required int dstX,
    required int dstY,
  });

  Uint8List encodePng(EngineImage image);
}
