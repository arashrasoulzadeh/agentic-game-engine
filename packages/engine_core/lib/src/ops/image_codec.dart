import 'dart:typed_data';

/// A decoded raster the packer and render ops share. Opaque to core — only the injected
/// [ImageCodec] creates, resizes and composites them (so `engine_core` never depends on
/// `package:image`).
abstract class EngineImage {
  int get width;
  int get height;
}

/// Decode / resize / encode for operations that need pixels (`asset.pack`, eventually
/// `level.lint --render`). `engine_cli` and `engine_api` each supply a thin wrapper over
/// `package:image`; without one those ops return [ErrorCode.unsupported].
abstract class ImageCodec {
  /// Decodes [bytes], or null when the bytes are not a recognised image.
  EngineImage? decode(Uint8List bytes);

  /// A fresh image at [scale] of [source]'s size (at least 1×1).
  EngineImage resize(EngineImage source, double scale);

  /// An empty (transparent) RGBA canvas.
  EngineImage create(int width, int height);

  /// Copies [src] onto [dest] at ([dstX], [dstY]) without blending.
  void composite(
    EngineImage dest,
    EngineImage src, {
    required int dstX,
    required int dstY,
  });

  Uint8List encodePng(EngineImage image);
}
