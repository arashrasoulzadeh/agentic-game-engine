import 'dart:typed_data';

import 'package:engine_core/engine_core_ops.dart';
import 'package:image/image.dart' as img;

/// [ImageCodec] backed by `package:image` — what `game_agent` and `engine_api` inject into [OpContext].
class PackageImageCodec implements ImageCodec {
  const PackageImageCodec();

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
