import 'dart:typed_data';

import 'package:engine_core/engine_core_ops.dart';
import 'package:image/image.dart' as img;

/// [ImageCodec] backed by `package:image` — injected into [OpContext] for `asset.pack`
/// and `level.lint` render. Same wrapper as `engine_cli`.
class PackageImageCodec implements ImageCodec {
  const PackageImageCodec();

  img.Color _c(EngineColor c) => img.ColorRgba8(c.r, c.g, c.b, c.a);

  @override
  EngineImage? decode(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    return decoded == null ? null : _Img(decoded);
  }

  @override
  EngineImage resize(EngineImage source, double scale) {
    final src = (source as _Img).image;
    return _Img(
      img.copyResize(
        src,
        width: (src.width * scale).round().clamp(1, 1 << 20),
        height: (src.height * scale).round().clamp(1, 1 << 20),
      ),
    );
  }

  @override
  EngineImage create(int width, int height) =>
      _Img(img.Image(width: width, height: height, numChannels: 4));

  @override
  void fill(EngineImage image, EngineColor color) {
    img.fill((image as _Img).image, color: _c(color));
  }

  @override
  void fillRect(
    EngineImage image, {
    required int x1,
    required int y1,
    required int x2,
    required int y2,
    required EngineColor color,
  }) {
    img.fillRect(
      (image as _Img).image,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      color: _c(color),
    );
  }

  @override
  void fillCircle(
    EngineImage image, {
    required int x,
    required int y,
    required int radius,
    required EngineColor color,
  }) {
    img.fillCircle(
      (image as _Img).image,
      x: x,
      y: y,
      radius: radius,
      color: _c(color),
    );
  }

  @override
  void drawString(
    EngineImage image,
    String text, {
    required int x,
    required int y,
    required EngineColor color,
  }) {
    img.drawString(
      (image as _Img).image,
      text,
      font: img.arial14,
      x: x,
      y: y,
      color: _c(color),
    );
  }

  @override
  void composite(
    EngineImage dest,
    EngineImage src, {
    required int dstX,
    required int dstY,
  }) {
    img.compositeImage(
      (dest as _Img).image,
      (src as _Img).image,
      dstX: dstX,
      dstY: dstY,
      blend: img.BlendMode.direct,
    );
  }

  @override
  Uint8List encodePng(EngineImage image) =>
      Uint8List.fromList(img.encodePng((image as _Img).image));
}

class _Img implements EngineImage {
  _Img(this.image);

  final img.Image image;

  @override
  int get width => image.width;

  @override
  int get height => image.height;
}
