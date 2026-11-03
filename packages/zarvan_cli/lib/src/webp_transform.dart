import 'dart:io';

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Runs `cwebp` with [args]; returns its exit code. Injectable so tests need
/// no encoder installed.
typedef WebpEncoder = int Function(List<String> args);

int _runCwebp(List<String> args) {
  try {
    return Process.runSync('cwebp', args).exitCode;
  } on ProcessException {
    return -1;
  }
}

/// True when [webp] decodes to the same visible pixels as [png].
///
/// Fully transparent pixels are compared only by alpha: their hidden colour
/// is never drawn, and cwebp is free to rewrite it for a smaller file.
///
/// A 16-bit PNG is compared at 8 bits per channel (what Flutter decodes it to
/// and all WebP can hold). The 16-to-8 rounding is the encoder's, and it may
/// turn a near-transparent pixel into a transparent one, so those images are
/// compared by what is drawn: alpha within one 8-bit level and
/// alpha-weighted colour within two. 8-bit PNGs must match exactly wherever alpha is not zero.
bool samePixels(List<int> png, List<int> webp) {
  final a = img.decodePng(Uint8List.fromList(png));
  final b = img.decodeWebP(Uint8List.fromList(webp));
  if (a == null || b == null) return false;
  if (a.width != b.width || a.height != b.height) return false;
  final wide = a.maxChannelValue > 255;
  int to8(num v, num max) => max == 255 ? v.toInt() : (v * 255 / max).round();
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final p = a.getPixel(x, y);
      final q = b.getPixel(x, y);
      final pa = to8(p.a, a.maxChannelValue);
      final qa = to8(q.a, b.maxChannelValue);
      final pc = [p.r, p.g, p.b].map((v) => to8(v, a.maxChannelValue)).toList();
      final qc = [q.r, q.g, q.b].map((v) => to8(v, b.maxChannelValue)).toList();
      if (wide) {
        if ((pa - qa).abs() > 1) return false;
        for (var c = 0; c < 3; c++) {
          if ((pc[c] * pa - qc[c] * qa).abs() > 510) return false;
        }
      } else {
        if (pa != qa) return false;
        if (pa == 0) continue;
        for (var c = 0; c < 3; c++) {
          if (pc[c] != qc[c]) return false;
        }
      }
    }
  }
  return true;
}

/// Flutter asset transformer body: writes [output] as the smallest valid form
/// of the image at [input].
///
/// A `.png` becomes lossless WebP when `cwebp` is available and the result is
/// smaller **and** [verify] confirms it decodes to the same visible pixels (the
/// build never trades quality); anything else (other formats, a missing encoder,
/// a larger or different result) is copied unchanged, so a build never fails or grows because of this step.
/// The asset keeps its name: Flutter's image codecs detect the format from the
/// bytes, so a WebP stored under a `.png` path loads exactly like the PNG.
/// Returns true when [output] holds WebP.
bool transformImage(
  String input,
  String output, {
  WebpEncoder encoder = _runCwebp,
  bool Function(List<int> png, List<int> webp) verify = samePixels,
}) {
  if (input.toLowerCase().endsWith('.png')) {
    final code = encoder([
      '-lossless',
      '-z',
      '6',
      '-quiet',
      input,
      '-o',
      output,
    ]);
    if (code == 0 &&
        File(output).existsSync() &&
        File(output).lengthSync() < File(input).lengthSync() &&
        verify(File(input).readAsBytesSync(), File(output).readAsBytesSync())) {
      return true;
    }
  }
  File(input).copySync(output);
  return false;
}
